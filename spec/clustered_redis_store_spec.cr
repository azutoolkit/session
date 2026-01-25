require "./spec_helper"

if REDIS_AVAILABLE
  describe Session::ClusteredRedisStore do
    describe "#initialize" do
      it "creates store with default config" do
        redis = redis_client
        store = Session::ClusteredRedisStore(UserSession).new(redis)

        store.storage.should contain "ClusteredRedisStore"
        store.storage.should contain "RedisStore"
        store.coordinator.running?.should be_false

        store.shutdown
        redis.close
      end

      it "creates store with clustering enabled" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true, node_id: "test-node")
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        sleep(50.milliseconds) # Allow coordinator to start
        store.coordinator.running?.should be_true
        store.coordinator.node_id.should eq "test-node"

        store.shutdown
        redis.close
      end

      it "creates store with custom local cache settings" do
        redis = redis_client
        config = Session::ClusterConfig.new(
          enabled: false,
          local_cache_enabled: true,
          local_cache_ttl: 1.minute,
          local_cache_max_size: 500
        )
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        store.coordinator.config.local_cache_ttl.should eq 1.minute
        store.coordinator.config.local_cache_max_size.should eq 500

        store.shutdown
        redis.close
      end
    end

    describe "#[] and #[]=" do
      it "stores and retrieves sessions" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        session = Session::SessionId(UserSession).new
        key = session.session_id

        store[key] = session
        retrieved = store[key]

        retrieved.session_id.should eq session.session_id
        retrieved.data.username.should eq session.data.username

        store.shutdown
        redis.close
      end

      it "returns cached session on second access" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        session = Session::SessionId(UserSession).new
        key = session.session_id

        store[key] = session

        # First access - should hit cache (was populated on set)
        store[key]
        stats = store.cache_stats
        stats.hits.should eq 1
        stats.misses.should eq 0

        # Second access - should hit cache again
        store[key]
        stats = store.cache_stats
        stats.hits.should eq 2

        store.shutdown
        redis.close
      end

      it "fetches from Redis on cache miss" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        session = Session::SessionId(UserSession).new
        key = session.session_id

        # Store in Redis directly (bypass cache)
        store.redis_store[key] = session

        # Access should miss cache but find in Redis
        retrieved = store[key]
        retrieved.session_id.should eq session.session_id

        stats = store.cache_stats
        stats.misses.should eq 1

        # Next access should hit cache
        store[key]
        stats = store.cache_stats
        stats.hits.should eq 1

        store.shutdown
        redis.close
      end

      it "works with cache disabled" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: false)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        session = Session::SessionId(UserSession).new
        key = session.session_id

        store[key] = session
        retrieved = store[key]

        retrieved.session_id.should eq session.session_id

        # No cache operations should have occurred
        stats = store.cache_stats
        stats.hits.should eq 0
        stats.misses.should eq 0

        store.shutdown
        redis.close
      end
    end

    describe "#[]?" do
      it "returns nil for missing sessions" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        store["nonexistent"]?.should be_nil

        store.shutdown
        redis.close
      end

      it "returns cached session if available" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        session = Session::SessionId(UserSession).new
        key = session.session_id

        store[key] = session

        store[key]?.should_not be_nil
        store.cache_stats.hits.should eq 1

        store.shutdown
        redis.close
      end
    end

    describe "#delete" do
      it "removes session from Redis and cache" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        session = Session::SessionId(UserSession).new
        key = session.session_id

        store[key] = session
        store[key]?.should_not be_nil

        store.delete(key)

        store[key]?.should be_nil
        store.coordinator.local_cache.get(key).should be_nil

        store.shutdown
        redis.close
      end

      it "broadcasts invalidation when clustering is enabled" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true, node_id: "deleter-node")
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        sleep(50.milliseconds) # Allow coordinator to start

        # Store session first (without subscriber listening)
        session = Session::SessionId(UserSession).new
        store[session.session_id] = session

        sleep(50.milliseconds) # Allow any messages to clear

        # Now set up subscriber to capture the delete message
        received_message : Session::ClusterMessage? = nil
        subscriber = Redis.new(host: REDIS_HOST)

        spawn do
          subscriber.subscribe(config.channel) do |on|
            on.message do |_channel, message|
              received_message = Session::ClusterMessage.from_json(message)
              subscriber.unsubscribe(config.channel)
            end
          end
        end

        sleep(50.milliseconds) # Allow subscriber to start

        store.delete(session.session_id)

        sleep(100.milliseconds) # Allow message to propagate

        received_message.should_not be_nil
        if msg = received_message
          msg.type.should eq Session::ClusterMessageType::SessionDeleted
          msg.session_id.should eq session.session_id
          msg.node_id.should eq "deleter-node"
        end

        store.shutdown
        redis.close
        subscriber.close rescue nil
      end
    end

    describe "#clear" do
      it "clears all sessions and local cache" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        # Clear any existing sessions from previous tests
        store.clear

        # Add multiple sessions
        3.times do
          session = Session::SessionId(UserSession).new
          store[session.session_id] = session
        end

        store.size.should eq 3
        store.coordinator.local_cache.size.should eq 3

        store.clear

        store.size.should eq 0
        store.coordinator.local_cache.size.should eq 0

        store.shutdown
        redis.close
      end

      it "broadcasts cache clear when clustering is enabled" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true, node_id: "clearer-node")
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        sleep(50.milliseconds)

        received_message : Session::ClusterMessage? = nil
        subscriber = Redis.new(host: REDIS_HOST)

        spawn do
          subscriber.subscribe(config.channel) do |on|
            on.message do |_channel, message|
              received_message = Session::ClusterMessage.from_json(message)
              subscriber.unsubscribe(config.channel)
            end
          end
        end

        sleep(50.milliseconds)

        store.clear

        sleep(100.milliseconds)

        received_message.should_not be_nil
        if msg = received_message
          msg.type.should eq Session::ClusterMessageType::CacheClear
          msg.node_id.should eq "clearer-node"
        end

        store.shutdown
        redis.close
        subscriber.close rescue nil
      end
    end

    describe "#size" do
      it "returns count from Redis store" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        5.times do
          session = Session::SessionId(UserSession).new
          store[session.session_id] = session
        end

        store.size.should eq 5

        store.clear
        store.shutdown
        redis.close
      end
    end

    describe "#healthy?" do
      it "returns true when Redis is available" do
        redis = redis_client
        store = Session::ClusteredRedisStore(UserSession).new(redis)

        store.healthy?.should be_true

        store.shutdown
        redis.close
      end
    end

    describe "#cache_stats" do
      it "returns local cache statistics" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        session = Session::SessionId(UserSession).new
        store[session.session_id] = session

        # Hit
        store[session.session_id]

        # Miss
        store["nonexistent"]?

        stats = store.cache_stats
        stats.hits.should eq 1
        stats.misses.should eq 1
        stats.size.should eq 1

        store.shutdown
        redis.close
      end
    end

    describe "#evict_from_cache" do
      it "removes entry from local cache only" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: false, local_cache_enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        session = Session::SessionId(UserSession).new
        store[session.session_id] = session

        # Verify it's in cache
        store.coordinator.local_cache.get(session.session_id).should_not be_nil

        # Evict from cache only
        store.evict_from_cache(session.session_id).should be_true

        # Should be gone from cache
        store.coordinator.local_cache.get(session.session_id).should be_nil

        # But still in Redis
        store[session.session_id]?.should_not be_nil

        store.shutdown
        redis.close
      end
    end

    describe "QueryableStore methods" do
      describe "#all_session_ids" do
        it "returns all session IDs from Redis" do
          redis = redis_client
          config = Session::ClusterConfig.new(enabled: false)
          store = Session::ClusteredRedisStore(UserSession).new(redis, config)

          ids = [] of String
          3.times do
            session = Session::SessionId(UserSession).new
            store[session.session_id] = session
            ids << session.session_id
          end

          all_ids = store.all_session_ids
          ids.each do |id|
            all_ids.should contain id
          end

          store.clear
          store.shutdown
          redis.close
        end
      end

      describe "#each_session" do
        it "iterates over all sessions" do
          redis = redis_client
          config = Session::ClusterConfig.new(enabled: false)
          store = Session::ClusteredRedisStore(UserSession).new(redis, config)

          3.times do
            session = Session::SessionId(UserSession).new
            store[session.session_id] = session
          end

          count = 0
          store.each_session do |_session|
            count += 1
          end

          count.should eq 3

          store.clear
          store.shutdown
          redis.close
        end
      end
    end

    describe "multi-node simulation" do
      it "evicts cache on invalidation from another node" do
        redis = redis_client

        # Create two stores simulating two nodes
        config1 = Session::ClusterConfig.new(enabled: true, node_id: "node-1")
        config2 = Session::ClusterConfig.new(enabled: true, node_id: "node-2")

        store1 = Session::ClusteredRedisStore(UserSession).new(redis, config1)
        store2 = Session::ClusteredRedisStore(UserSession).new(Redis.new(host: REDIS_HOST), config2)

        sleep(100.milliseconds) # Allow coordinators to start

        # Store session via node 1
        session = Session::SessionId(UserSession).new
        store1[session.session_id] = session

        # Load session on node 2 (populates its cache)
        store2[session.session_id]
        store2.coordinator.local_cache.get(session.session_id).should_not be_nil

        # Delete on node 1
        store1.delete(session.session_id)

        sleep(150.milliseconds) # Allow invalidation to propagate

        # Node 2's cache should be invalidated
        store2.coordinator.local_cache.get(session.session_id).should be_nil

        store1.shutdown
        store2.shutdown
        redis.close
      end

      it "clears cache on cache clear from another node" do
        redis = redis_client

        config1 = Session::ClusterConfig.new(enabled: true, node_id: "node-1")
        config2 = Session::ClusterConfig.new(enabled: true, node_id: "node-2")

        store1 = Session::ClusteredRedisStore(UserSession).new(redis, config1)
        store2 = Session::ClusteredRedisStore(UserSession).new(Redis.new(host: REDIS_HOST), config2)

        sleep(100.milliseconds)

        # Add sessions to node 2's cache
        3.times do
          session = Session::SessionId(UserSession).new
          store1[session.session_id] = session
          store2[session.session_id] # Populate node 2's cache
        end

        store2.coordinator.local_cache.size.should eq 3

        # Clear from node 1
        store1.clear

        sleep(150.milliseconds)

        # Node 2's cache should be cleared
        store2.coordinator.local_cache.size.should eq 0

        store1.shutdown
        store2.shutdown
        redis.close
      end

      it "does not process own invalidation messages" do
        redis = redis_client

        config = Session::ClusterConfig.new(enabled: true, node_id: "same-node")
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        sleep(50.milliseconds)

        session = Session::SessionId(UserSession).new
        store[session.session_id] = session

        # Manually add to cache again to ensure it's there
        store.coordinator.local_cache.set(session.session_id, session)

        # Delete - this will broadcast invalidation
        store.delete(session.session_id)

        # Add back to cache
        store.coordinator.local_cache.set(session.session_id, session)

        sleep(100.milliseconds)

        # Cache should still have the session because we ignore our own messages
        store.coordinator.local_cache.get(session.session_id).should_not be_nil

        store.shutdown
        redis.close
      end
    end

    describe "#shutdown" do
      it "stops coordinator and closes Redis connection gracefully" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true)
        store = Session::ClusteredRedisStore(UserSession).new(redis, config)

        sleep(50.milliseconds)
        store.coordinator.running?.should be_true

        store.shutdown

        sleep(50.milliseconds)
        store.coordinator.running?.should be_false
      end
    end
  end
end
