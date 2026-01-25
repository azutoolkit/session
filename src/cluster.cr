require "redis"
require "json"
require "uuid"

module Session
  # ClusterConfig is defined in configuration.cr

  # Message types for cluster pub/sub communication
  enum ClusterMessageType
    SessionDeleted
    SessionInvalidated
    CacheClear
  end

  # Message structure for cluster communication
  struct ClusterMessage
    include JSON::Serializable

    property type : ClusterMessageType
    property session_id : String
    property node_id : String
    property timestamp : Time

    def initialize(
      @type : ClusterMessageType,
      @session_id : String,
      @node_id : String,
      @timestamp : Time = Time.utc
    )
    end
  end

  # Local cache with TTL and LRU eviction for session data
  class LocalCache(T)
    struct CacheEntry(T)
      property value : T
      property expires_at : Time
      property last_accessed : Time

      def initialize(@value : T, @expires_at : Time, @last_accessed : Time = Time.utc)
      end

      def expired? : Bool
        Time.utc > @expires_at
      end
    end

    struct CacheStats
      property hits : Int64
      property misses : Int64
      property evictions : Int64
      property size : Int32

      def initialize(@hits : Int64, @misses : Int64, @evictions : Int64, @size : Int32)
      end

      def hit_rate : Float64
        total = @hits + @misses
        return 0.0 if total == 0
        @hits.to_f64 / total.to_f64
      end
    end

    @cache : Hash(String, CacheEntry(T))
    @mutex : Mutex
    @ttl : Time::Span
    @max_size : Int32
    @hits : Int64 = 0_i64
    @misses : Int64 = 0_i64
    @evictions : Int64 = 0_i64

    def initialize(@ttl : Time::Span = 30.seconds, @max_size : Int32 = 10_000)
      @cache = Hash(String, CacheEntry(T)).new
      @mutex = Mutex.new
    end

    # Get a value from the cache, returning nil if expired or missing
    def get(key : String) : T?
      @mutex.synchronize do
        if entry = @cache[key]?
          if entry.expired?
            @cache.delete(key)
            @misses += 1
            nil
          else
            # Update last_accessed for LRU tracking
            @cache[key] = CacheEntry(T).new(
              value: entry.value,
              expires_at: entry.expires_at,
              last_accessed: Time.utc
            )
            @hits += 1
            entry.value
          end
        else
          @misses += 1
          nil
        end
      end
    end

    # Store a value in the cache with automatic TTL
    def set(key : String, value : T) : T
      @mutex.synchronize do
        # Evict LRU entries if at max size
        evict_lru_if_needed

        @cache[key] = CacheEntry(T).new(
          value: value,
          expires_at: Time.utc + @ttl,
          last_accessed: Time.utc
        )
        value
      end
    end

    # Remove a key from the cache
    def delete(key : String) : Bool
      @mutex.synchronize do
        @cache.delete(key) != nil
      end
    end

    # Clear all entries from the cache
    def clear : Nil
      @mutex.synchronize do
        @cache.clear
      end
    end

    # Count of valid (non-expired) entries
    def size : Int32
      @mutex.synchronize do
        cleanup_expired
        @cache.size
      end
    end

    # Get cache statistics
    def stats : CacheStats
      @mutex.synchronize do
        cleanup_expired
        CacheStats.new(
          hits: @hits,
          misses: @misses,
          evictions: @evictions,
          size: @cache.size
        )
      end
    end

    # Reset statistics counters
    def reset_stats : Nil
      @mutex.synchronize do
        @hits = 0_i64
        @misses = 0_i64
        @evictions = 0_i64
      end
    end

    private def evict_lru_if_needed
      return if @cache.size < @max_size

      # Remove expired entries first
      cleanup_expired

      # If still at max, evict least recently used
      while @cache.size >= @max_size
        lru_key = find_lru_key
        if lru_key
          @cache.delete(lru_key)
          @evictions += 1
        else
          break
        end
      end
    end

    private def cleanup_expired
      @cache.reject! { |_, entry| entry.expired? }
    end

    private def find_lru_key : String?
      return nil if @cache.empty?

      oldest_key : String? = nil
      oldest_time : Time? = nil

      @cache.each do |key, entry|
        current_oldest = oldest_time
        if current_oldest.nil? || entry.last_accessed < current_oldest
          oldest_key = key
          oldest_time = entry.last_accessed
        end
      end

      oldest_key
    end
  end

  # Main cluster coordinator for managing pub/sub and local caching
  class ClusterCoordinator(T)
    getter local_cache : LocalCache(SessionId(T))
    getter node_id : String
    getter config : ClusterConfig

    @redis : Redis
    @subscriber : Redis?
    @running : Bool = false
    @subscription_fiber : Fiber?
    @mutex : Mutex = Mutex.new

    def initialize(@redis : Redis, @config : ClusterConfig = ClusterConfig.new)
      @node_id = @config.node_id
      @local_cache = LocalCache(SessionId(T)).new(
        ttl: @config.local_cache_ttl,
        max_size: @config.local_cache_max_size
      )
    end

    # Start the background subscription fiber
    def start : Nil
      @mutex.synchronize do
        return if @running
        @running = true
      end

      @subscription_fiber = spawn { subscription_loop }
      Log.info { "Cluster coordinator started for node #{@node_id}" }
    end

    # Gracefully stop the coordinator
    def stop : Nil
      @mutex.synchronize do
        return unless @running
        @running = false
      end

      @subscriber.try do |sub|
        begin
          sub.unsubscribe(@config.channel)
        rescue ex : Exception
          Log.warn { "Error unsubscribing from cluster channel: #{ex.message}" }
        end

        begin
          sub.close
        rescue ex : Exception
          Log.warn { "Error closing subscriber connection: #{ex.message}" }
        end
      end

      @subscriber = nil
      Log.info { "Cluster coordinator stopped for node #{@node_id}" }
    end

    # Check if the coordinator is running
    def running? : Bool
      @mutex.synchronize { @running }
    end

    # Publish a session invalidation message to the cluster
    def publish_invalidation(session_id : String) : Nil
      message = ClusterMessage.new(
        type: ClusterMessageType::SessionDeleted,
        session_id: session_id,
        node_id: @node_id,
        timestamp: Time.utc
      )
      publish_message(message)
    end

    # Publish a session updated message (for invalidation on update)
    def publish_session_invalidated(session_id : String) : Nil
      message = ClusterMessage.new(
        type: ClusterMessageType::SessionInvalidated,
        session_id: session_id,
        node_id: @node_id,
        timestamp: Time.utc
      )
      publish_message(message)
    end

    # Publish a cache clear message to all nodes
    def publish_cache_clear : Nil
      message = ClusterMessage.new(
        type: ClusterMessageType::CacheClear,
        session_id: "",
        node_id: @node_id,
        timestamp: Time.utc
      )
      publish_message(message)
    end

    private def publish_message(message : ClusterMessage) : Nil
      @redis.publish(@config.channel, message.to_json)
      Log.debug { "Published cluster message: #{message.type} for session #{message.session_id}" }
    rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
      Log.warn { "Failed to publish cluster message: #{ex.message}" }
    rescue ex : Exception
      Log.warn { "Unexpected error publishing cluster message: #{ex.message}" }
    end

    private def subscription_loop
      Log.debug { "Starting subscription loop for node #{@node_id}" }

      while @running
        begin
          # Create a new Redis connection for subscription
          # Subscriptions require a dedicated connection
          @subscriber = create_subscriber_connection

          @subscriber.try do |sub|
            sub.subscribe(@config.channel) do |on|
              on.message do |_channel, message|
                handle_message(message) if @running
              end
            end
          end
        rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
          Log.warn { "Cluster subscription connection error: #{ex.message}" }
          sleep(1.second) if @running
        rescue ex : Exception
          Log.warn { "Cluster subscription error: #{ex.message}" }
          sleep(1.second) if @running
        end
      end

      Log.debug { "Subscription loop ended for node #{@node_id}" }
    end

    private def create_subscriber_connection : Redis
      # Extract connection params from the existing Redis connection
      # and create a new connection for subscriptions
      Redis.new(
        host: @redis.@host,
        port: @redis.@port,
        password: @redis.@password,
        database: @redis.@database
      )
    rescue ex : Exception
      Log.error { "Failed to create subscriber connection: #{ex.message}" }
      raise ClusterConnectionException.new("Failed to create cluster subscriber connection", ex)
    end

    private def handle_message(raw : String)
      message = ClusterMessage.from_json(raw)

      # Ignore messages from self (same node_id)
      if message.node_id == @node_id
        Log.debug { "Ignoring own cluster message: #{message.type}" }
        return
      end

      case message.type
      when .session_deleted?, .session_invalidated?
        @local_cache.delete(message.session_id)
        Log.debug { "Evicted session #{message.session_id} from local cache (from node #{message.node_id})" }
      when .cache_clear?
        @local_cache.clear
        Log.debug { "Cleared local cache (from node #{message.node_id})" }
      end
    rescue ex : JSON::ParseException
      Log.warn { "Failed to parse cluster message: #{ex.message}" }
    rescue ex : Exception
      Log.warn { "Error handling cluster message: #{ex.message}" }
    end
  end
end
