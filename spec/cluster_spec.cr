require "./spec_helper"

describe Session::ClusterConfig do
  describe "#initialize" do
    it "creates config with default values" do
      config = Session::ClusterConfig.new
      config.enabled.should be_false
      config.node_id.should_not be_empty
      config.channel.should eq "session:cluster:invalidate"
      config.local_cache_enabled.should be_true
      config.local_cache_ttl.should eq 30.seconds
      config.local_cache_max_size.should eq 10_000
      config.subscribe_timeout.should eq 5.seconds
    end

    it "creates config with custom values" do
      config = Session::ClusterConfig.new(
        enabled: true,
        node_id: "node-1",
        channel: "custom:channel",
        local_cache_enabled: false,
        local_cache_ttl: 1.minute,
        local_cache_max_size: 5_000,
        subscribe_timeout: 10.seconds
      )
      config.enabled.should be_true
      config.node_id.should eq "node-1"
      config.channel.should eq "custom:channel"
      config.local_cache_enabled.should be_false
      config.local_cache_ttl.should eq 1.minute
      config.local_cache_max_size.should eq 5_000
      config.subscribe_timeout.should eq 10.seconds
    end
  end
end

describe Session::ClusterMessage do
  describe "#to_json and .from_json" do
    it "serializes and deserializes correctly" do
      message = Session::ClusterMessage.new(
        type: Session::ClusterMessageType::SessionDeleted,
        session_id: "test-session-123",
        node_id: "node-1",
        timestamp: Time.utc(2024, 1, 15, 12, 0, 0)
      )

      json = message.to_json
      parsed = Session::ClusterMessage.from_json(json)

      parsed.type.should eq Session::ClusterMessageType::SessionDeleted
      parsed.session_id.should eq "test-session-123"
      parsed.node_id.should eq "node-1"
      parsed.timestamp.should eq Time.utc(2024, 1, 15, 12, 0, 0)
    end

    it "handles all message types" do
      [
        Session::ClusterMessageType::SessionDeleted,
        Session::ClusterMessageType::SessionInvalidated,
        Session::ClusterMessageType::CacheClear,
      ].each do |type|
        message = Session::ClusterMessage.new(
          type: type,
          session_id: "session-id",
          node_id: "node-id"
        )

        parsed = Session::ClusterMessage.from_json(message.to_json)
        parsed.type.should eq type
      end
    end
  end
end

describe Session::LocalCache do
  describe "#get and #set" do
    it "stores and retrieves values" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      cache.set("key1", "value1")
      cache.get("key1").should eq "value1"
    end

    it "returns nil for missing keys" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      cache.get("nonexistent").should be_nil
    end

    it "returns nil for expired entries" do
      cache = Session::LocalCache(String).new(ttl: 1.millisecond)

      cache.set("key1", "value1")
      sleep(5.milliseconds)
      cache.get("key1").should be_nil
    end

    it "updates last_accessed on get" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      cache.set("key1", "value1")
      sleep(10.milliseconds)

      # Get should update last_accessed
      cache.get("key1").should eq "value1"

      # Stats should show a hit
      stats = cache.stats
      stats.hits.should eq 1
    end
  end

  describe "#delete" do
    it "removes existing entries and returns true" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      cache.set("key1", "value1")
      cache.delete("key1").should be_true
      cache.get("key1").should be_nil
    end

    it "returns false for non-existent keys" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      cache.delete("nonexistent").should be_false
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      cache.clear
      cache.size.should eq 0
      cache.get("key1").should be_nil
      cache.get("key2").should be_nil
      cache.get("key3").should be_nil
    end
  end

  describe "#size" do
    it "returns count of valid entries" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      cache.set("key1", "value1")
      cache.set("key2", "value2")

      cache.size.should eq 2
    end

    it "excludes expired entries" do
      cache = Session::LocalCache(String).new(ttl: 1.millisecond)

      cache.set("key1", "value1")
      sleep(5.milliseconds)

      cache.size.should eq 0
    end
  end

  describe "#stats" do
    it "tracks hits, misses, and evictions" do
      cache = Session::LocalCache(String).new(ttl: 1.minute, max_size: 2)

      # Initial stats
      stats = cache.stats
      stats.hits.should eq 0
      stats.misses.should eq 0
      stats.evictions.should eq 0

      # Add entries
      cache.set("key1", "value1")
      cache.set("key2", "value2")

      # Hit
      cache.get("key1")

      # Miss
      cache.get("nonexistent")

      # Force eviction
      cache.set("key3", "value3")

      stats = cache.stats
      stats.hits.should eq 1
      stats.misses.should eq 1
      stats.evictions.should be >= 1
    end

    it "calculates hit rate correctly" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      cache.set("key1", "value1")

      # 2 hits
      cache.get("key1")
      cache.get("key1")

      # 2 misses
      cache.get("miss1")
      cache.get("miss2")

      stats = cache.stats
      stats.hit_rate.should eq 0.5
    end

    it "returns 0 hit rate with no operations" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      stats = cache.stats
      stats.hit_rate.should eq 0.0
    end
  end

  describe "LRU eviction" do
    it "evicts least recently used entries when at max size" do
      cache = Session::LocalCache(String).new(ttl: 1.minute, max_size: 3)

      cache.set("key1", "value1")
      sleep(1.millisecond)
      cache.set("key2", "value2")
      sleep(1.millisecond)
      cache.set("key3", "value3")

      # Access key1 to make it recently used
      cache.get("key1")
      sleep(1.millisecond)

      # Add new entry, should evict key2 (least recently used)
      cache.set("key4", "value4")

      cache.get("key1").should eq "value1" # Recently accessed
      cache.get("key2").should be_nil      # Should be evicted
      cache.get("key3").should eq "value3"
      cache.get("key4").should eq "value4"
    end
  end

  describe "#reset_stats" do
    it "resets all counters" do
      cache = Session::LocalCache(String).new(ttl: 1.minute)

      cache.set("key1", "value1")
      cache.get("key1")
      cache.get("miss")

      cache.reset_stats

      stats = cache.stats
      stats.hits.should eq 0
      stats.misses.should eq 0
      stats.evictions.should eq 0
    end
  end
end

describe Session::ClusterMessageType do
  describe "#session_deleted?" do
    it "returns true for SessionDeleted" do
      Session::ClusterMessageType::SessionDeleted.session_deleted?.should be_true
    end

    it "returns false for other types" do
      Session::ClusterMessageType::SessionInvalidated.session_deleted?.should be_false
      Session::ClusterMessageType::CacheClear.session_deleted?.should be_false
    end
  end

  describe "#session_invalidated?" do
    it "returns true for SessionInvalidated" do
      Session::ClusterMessageType::SessionInvalidated.session_invalidated?.should be_true
    end
  end

  describe "#cache_clear?" do
    it "returns true for CacheClear" do
      Session::ClusterMessageType::CacheClear.cache_clear?.should be_true
    end
  end
end

# Integration tests with Redis (only run if Redis is available)
if REDIS_AVAILABLE
  describe Session::ClusterCoordinator do
    describe "#initialize" do
      it "creates coordinator with default config" do
        redis = redis_client
        coordinator = Session::ClusterCoordinator(UserSession).new(redis)

        coordinator.node_id.should_not be_empty
        coordinator.config.enabled.should be_false
        coordinator.running?.should be_false

        redis.close
      end

      it "creates coordinator with custom config" do
        redis = redis_client
        config = Session::ClusterConfig.new(
          enabled: true,
          node_id: "test-node-1",
          local_cache_ttl: 1.minute
        )
        coordinator = Session::ClusterCoordinator(UserSession).new(redis, config)

        coordinator.node_id.should eq "test-node-1"
        coordinator.config.local_cache_ttl.should eq 1.minute

        redis.close
      end
    end

    describe "#start and #stop" do
      it "starts and stops the coordinator" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true)
        coordinator = Session::ClusterCoordinator(UserSession).new(redis, config)

        coordinator.running?.should be_false

        coordinator.start
        sleep(50.milliseconds) # Allow fiber to start
        coordinator.running?.should be_true

        coordinator.stop
        sleep(50.milliseconds) # Allow fiber to stop
        coordinator.running?.should be_false

        redis.close
      end

      it "handles multiple start calls gracefully" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true)
        coordinator = Session::ClusterCoordinator(UserSession).new(redis, config)

        coordinator.start
        coordinator.start # Should not error
        coordinator.running?.should be_true

        coordinator.stop
        redis.close
      end

      it "handles multiple stop calls gracefully" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true)
        coordinator = Session::ClusterCoordinator(UserSession).new(redis, config)

        coordinator.start
        sleep(50.milliseconds)

        coordinator.stop
        coordinator.stop # Should not error
        coordinator.running?.should be_false

        redis.close
      end
    end

    describe "#publish_invalidation" do
      it "publishes a session deleted message" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true, node_id: "publisher-node")
        coordinator = Session::ClusterCoordinator(UserSession).new(redis, config)

        # Set up a subscriber to receive the message
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

        coordinator.publish_invalidation("test-session-id")

        sleep(100.milliseconds) # Allow message to propagate

        received_message.should_not be_nil
        if msg = received_message
          msg.type.should eq Session::ClusterMessageType::SessionDeleted
          msg.session_id.should eq "test-session-id"
          msg.node_id.should eq "publisher-node"
        end

        redis.close
        subscriber.close rescue nil
      end
    end

    describe "#publish_cache_clear" do
      it "publishes a cache clear message" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true, node_id: "publisher-node")
        coordinator = Session::ClusterCoordinator(UserSession).new(redis, config)

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

        coordinator.publish_cache_clear

        sleep(100.milliseconds)

        received_message.should_not be_nil
        if msg = received_message
          msg.type.should eq Session::ClusterMessageType::CacheClear
          msg.session_id.should eq ""
          msg.node_id.should eq "publisher-node"
        end

        redis.close
        subscriber.close rescue nil
      end
    end

    describe "message handling" do
      it "ignores messages from the same node" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true, node_id: "same-node")
        coordinator = Session::ClusterCoordinator(UserSession).new(redis, config)

        coordinator.start
        sleep(50.milliseconds)

        # Add something to the cache
        session = Session::SessionId(UserSession).new
        coordinator.local_cache.set(session.session_id, session)

        # Publish from the same node
        coordinator.publish_invalidation(session.session_id)
        sleep(100.milliseconds)

        # Cache should still have the session (message was ignored)
        coordinator.local_cache.get(session.session_id).should_not be_nil

        coordinator.stop
        redis.close
      end

      it "processes messages from different nodes" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true, node_id: "node-1")
        coordinator = Session::ClusterCoordinator(UserSession).new(redis, config)

        coordinator.start
        sleep(50.milliseconds)

        # Add something to the cache
        session = Session::SessionId(UserSession).new
        coordinator.local_cache.set(session.session_id, session)

        # Simulate a message from a different node
        message = Session::ClusterMessage.new(
          type: Session::ClusterMessageType::SessionDeleted,
          session_id: session.session_id,
          node_id: "node-2" # Different node
        )
        redis.publish(config.channel, message.to_json)
        sleep(100.milliseconds)

        # Cache should no longer have the session
        coordinator.local_cache.get(session.session_id).should be_nil

        coordinator.stop
        redis.close
      end

      it "clears cache on CacheClear message from different node" do
        redis = redis_client
        config = Session::ClusterConfig.new(enabled: true, node_id: "node-1")
        coordinator = Session::ClusterCoordinator(UserSession).new(redis, config)

        coordinator.start
        sleep(50.milliseconds)

        # Add multiple sessions to the cache
        3.times do |i|
          session = Session::SessionId(UserSession).new
          coordinator.local_cache.set("session-#{i}", session)
        end

        coordinator.local_cache.size.should eq 3

        # Simulate a cache clear message from a different node
        message = Session::ClusterMessage.new(
          type: Session::ClusterMessageType::CacheClear,
          session_id: "",
          node_id: "node-2"
        )
        redis.publish(config.channel, message.to_json)
        sleep(100.milliseconds)

        # Cache should be empty
        coordinator.local_cache.size.should eq 0

        coordinator.stop
        redis.close
      end
    end
  end
end

describe "Cluster exceptions" do
  it "creates ClusterException with message" do
    ex = Session::ClusterException.new("test error")
    ex.message.should eq "test error"
    ex.cause.should be_nil
  end

  it "creates ClusterConnectionException with cause" do
    cause = Exception.new("inner error")
    ex = Session::ClusterConnectionException.new("connection failed", cause)
    ex.message.should eq "connection failed"
    ex.cause.should eq cause
  end

  it "creates ClusterSubscriptionException" do
    ex = Session::ClusterSubscriptionException.new("subscription failed")
    ex.message.should eq "subscription failed"
  end
end
