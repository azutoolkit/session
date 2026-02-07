require "redis"

module Session
  # A Redis store with local caching and cluster-wide invalidation via pub/sub
  #
  # This store wraps RedisStore to provide:
  # - Local caching layer for reduced Redis load
  # - Pub/sub invalidation for multi-node deployments
  # - Automatic cache warming on miss
  # - Cluster-aware operations
  #
  # Example:
  # ```
  # Session.configure do |config|
  #   config.cluster.enabled = true
  #   config.cluster.node_id = ENV["NODE_ID"]? || UUID.random.to_s
  #
  #   config.provider = Session::ClusteredRedisStore(UserSession).new(
  #     client: Redis.new(host: "redis.example.com")
  #   )
  # end
  # ```
  class ClusteredRedisStore(T) < Store(T)
    include QueryableStore(T)

    getter redis_store : RedisStore(T)
    getter coordinator : ClusterCoordinator(T)
    getter circuit_breaker : CircuitBreaker?
    property current_session : SessionId(T) = SessionId(T).new

    def initialize(@client : Redis = Redis.new, config : ClusterConfig = ClusterConfig.new)
      @redis_store = RedisStore(T).new(@client)
      @coordinator = ClusterCoordinator(T).new(@client, config)
      @circuit_breaker = @redis_store.circuit_breaker

      if config.enabled
        @coordinator.start
      end
    end

    def storage : String
      "#{self.class.name} (backed by #{@redis_store.storage})"
    end

    def [](key : String) : SessionId(T)
      # Check local cache first
      if @coordinator.config.local_cache_enabled
        if cached = @coordinator.local_cache.get(key)
          Log.debug { "Local cache hit for session #{key}" }
          return cached
        end
        Log.debug { "Local cache miss for session #{key}" }
      end

      # Fetch from Redis
      session = @redis_store[key]

      # Populate local cache
      if @coordinator.config.local_cache_enabled
        @coordinator.local_cache.set(key, session)
      end

      session
    end

    def []?(key : String) : SessionId(T)?
      # Check local cache first
      if @coordinator.config.local_cache_enabled
        if cached = @coordinator.local_cache.get(key)
          Log.debug { "Local cache hit for session #{key}" }
          return cached
        end
        Log.debug { "Local cache miss for session #{key}" }
      end

      # Fetch from Redis
      if session = @redis_store[key]?
        # Populate local cache
        if @coordinator.config.local_cache_enabled
          @coordinator.local_cache.set(key, session)
        end
        session
      end
    end

    def []=(key : String, session : SessionId(T)) : SessionId(T)
      # Store in Redis
      @redis_store[key] = session

      # Update local cache
      if @coordinator.config.local_cache_enabled
        @coordinator.local_cache.set(key, session)
      end

      # Broadcast invalidation to cluster so other nodes refresh
      # This ensures eventual consistency across nodes
      if @coordinator.config.enabled && @coordinator.running?
        @coordinator.publish_session_invalidated(key)
      end

      session
    end

    def delete(key : String)
      # Delete from Redis
      @redis_store.delete(key)

      # Remove from local cache
      @coordinator.local_cache.delete(key)

      # Broadcast invalidation to cluster
      if @coordinator.config.enabled && @coordinator.running?
        @coordinator.publish_invalidation(key)
      end
    end

    def size : Int64
      @redis_store.size
    end

    def clear
      @redis_store.clear
      @coordinator.local_cache.clear

      # Broadcast cache clear to cluster
      if @coordinator.config.enabled && @coordinator.running?
        @coordinator.publish_cache_clear
      end
    end

    # Health check for the underlying Redis store
    def healthy? : Bool
      @redis_store.healthy?
    end

    # Graceful shutdown - stops coordinator and closes Redis connection
    def shutdown
      @coordinator.stop
      @redis_store.shutdown
    end

    # Get local cache statistics
    def cache_stats : LocalCache::CacheStats
      @coordinator.local_cache.stats
    end

    # Manually evict a session from the local cache (useful for testing)
    def evict_from_cache(key : String) : Bool
      @coordinator.local_cache.delete(key)
    end

    # QueryableStore implementation - delegate to redis_store

    def each_session(&block : SessionId(T) -> Nil) : Nil
      @redis_store.each_session(&block)
    end

    def bulk_delete(&predicate : SessionId(T) -> Bool) : Int64
      deleted_count = 0_i64

      # We need to track which sessions are deleted to broadcast invalidations
      if @coordinator.config.enabled && @coordinator.running?
        # Iterate through sessions and delete matching ones, broadcasting invalidations
        cursor = "0"
        pattern = "session:*"

        loop do
          result = @client.scan(cursor, match: pattern, count: 100)
          cursor = result[0].as(String)
          keys = result[1].as(Array(Redis::RedisValue))

          keys.each do |key|
            key_str = key.as(String)
            session_key = key_str.sub("session:", "")

            if session = @redis_store[session_key]?
              if predicate.call(session)
                @redis_store.delete(session_key)
                @coordinator.local_cache.delete(session_key)
                @coordinator.publish_invalidation(session_key)
                deleted_count += 1
              end
            end
          end

          break if cursor == "0"
        end

        deleted_count
      else
        # No clustering, just delegate and clear local cache entries as needed
        @redis_store.bulk_delete do |session|
          if predicate.call(session)
            @coordinator.local_cache.delete(session.session_id)
            true
          else
            false
          end
        end
      end
    rescue ex : Exception
      Log.warn { "Error during bulk delete: #{ex.message}" }
      deleted_count
    end

    def all_session_ids : Array(String)
      @redis_store.all_session_ids
    end
  end
end
