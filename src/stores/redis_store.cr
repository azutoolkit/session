require "redis"
require "../store"

module Session
  class RedisStore(T) < Store(T)
    include QueryableStore(T)
    getter circuit_breaker : CircuitBreaker?
    property current_session : T = T.new

    @client : Redis?
    @pool : ConnectionPool?

    # Initialize with either a Redis client or a ConnectionPool
    # When using a pool, pass it as the pool parameter
    # When using a direct client, pass it as the client parameter
    def initialize(client : Redis? = nil, pool : ConnectionPool? = nil)
      if pool
        @pool = pool
        @client = nil
      elsif client
        @client = client
        @pool = nil
      else
        # Default: create a new Redis client
        @client = Redis.new
        @pool = nil
      end

      if Session.config.circuit_breaker_enabled
        @circuit_breaker = CircuitBreaker.new(Session.config.circuit_breaker_config)
      end
    end

    # Convenience factory method for connection pool
    def self.with_pool(pool : ConnectionPool) : self
      new(pool: pool)
    end

    # Convenience factory method for pool config
    def self.with_pool(config : ConnectionPoolConfig) : self
      pool = ConnectionPool.new(config)
      new(pool: pool)
    end

    def storage : String
      self.class.name
    end

    def [](key : String) : T
      with_circuit_breaker do
        Retry.with_retry_if(
          ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
          Session.config.retry_config
        ) do
          with_redis_connection do |client|
            if data = client.get(prefixed(key))
              begin
                json_data = decrypt_if_enabled(data)
                T.from_json(json_data)
              rescue ex : Session::SessionEncryptionException
                Log.error { "Failed to decrypt session data for key #{key}: #{ex.message}" }
                raise SessionCorruptionException.new("Session decryption failed", ex)
              rescue ex : JSON::ParseException
                Log.error { "Failed to parse session data for key #{key}: #{ex.message}" }
                raise SessionCorruptionException.new("Invalid JSON in session data", ex)
              rescue ex : Exception
                Log.error { "Failed to deserialize session data for key #{key}: #{ex.message}" }
                raise SessionSerializationException.new("Session deserialization failed", ex)
              end
            else
              raise SessionNotFoundException.new("Session not found: #{key}")
            end
          end
        end
      end
    rescue ex : CircuitOpenException
      Log.error { "Circuit breaker open while retrieving session #{key}: #{ex.message}" }
      raise StorageConnectionException.new("Redis circuit breaker open", ex)
    rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
      Log.error { "Redis connection error while retrieving session #{key}: #{ex.message}" }
      raise StorageConnectionException.new("Redis connection failed", ex)
    rescue ex : Session::SessionExpiredException | Session::SessionCorruptionException | Session::SessionNotFoundException
      raise ex
    rescue ex : Exception
      Log.error { "Unexpected error while retrieving session #{key}: #{ex.message}" }
      raise SessionValidationException.new("Session retrieval failed", ex)
    end

    def []?(key : String) : T?
      with_circuit_breaker do
        Retry.with_retry_if(
          ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
          Session.config.retry_config
        ) do
          with_redis_connection do |client|
            if data = client.get(prefixed(key))
              begin
                json_data = decrypt_if_enabled(data)
                T.from_json(json_data)
              rescue ex : Session::SessionEncryptionException
                Log.warn { "Failed to decrypt session data for key #{key}: #{ex.message}" }
                nil
              rescue ex : JSON::ParseException
                Log.warn { "Failed to parse session data for key #{key}: #{ex.message}" }
                nil
              rescue ex : Exception
                Log.warn { "Failed to deserialize session data for key #{key}: #{ex.message}" }
                nil
              end
            end
          end
        end
      end
    rescue ex : CircuitOpenException
      Log.warn { "Circuit breaker open while retrieving session #{key}: #{ex.message}" }
      nil
    rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
      Log.warn { "Redis connection error while retrieving session #{key}: #{ex.message}" }
      nil
    rescue ex : Exception
      Log.warn { "Unexpected error while retrieving session #{key}: #{ex.message}" }
      nil
    end

    def []=(key : String, session : T) : T
      with_circuit_breaker do
        Retry.with_retry_if(
          ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
          Session.config.retry_config
        ) do
          with_redis_connection do |client|
            begin
              session_json = session.to_json
              data_to_store = encrypt_if_enabled(session_json)
              client.setex(prefixed(key), timeout.total_seconds.to_i, data_to_store)
              session
            rescue ex : Session::SessionEncryptionException
              Log.error { "Failed to encrypt session data for key #{key}: #{ex.message}" }
              raise ex
            rescue ex : JSON::ParseException
              Log.error { "Failed to serialize session data for key #{key}: #{ex.message}" }
              raise SessionSerializationException.new("Session serialization failed", ex)
            rescue ex : Exception
              Log.error { "Failed to store session data for key #{key}: #{ex.message}" }
              raise SessionValidationException.new("Session storage failed", ex)
            end
          end
        end
      end
    rescue ex : CircuitOpenException
      Log.error { "Circuit breaker open while storing session #{key}: #{ex.message}" }
      raise StorageConnectionException.new("Redis circuit breaker open", ex)
    rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
      Log.error { "Redis connection error while storing session #{key}: #{ex.message}" }
      raise StorageConnectionException.new("Redis connection failed", ex)
    rescue ex : Session::SessionSerializationException | Session::SessionValidationException | Session::SessionEncryptionException
      raise ex
    rescue ex : Exception
      Log.error { "Unexpected error while storing session #{key}: #{ex.message}" }
      raise SessionValidationException.new("Session storage failed", ex)
    end

    def delete(key : String)
      with_circuit_breaker do
        Retry.with_retry_if(
          ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
          Session.config.retry_config
        ) do
          with_redis_connection(&.del(prefixed(key)))
        end
      end
    rescue ex : CircuitOpenException
      Log.warn { "Circuit breaker open while deleting session #{key}: #{ex.message}" }
      # Don't raise on delete failures - session will expire naturally
    rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
      Log.warn { "Redis connection error while deleting session #{key}: #{ex.message}" }
      # Don't raise on delete failures - session will expire naturally
    rescue ex : Exception
      Log.warn { "Unexpected error while deleting session #{key}: #{ex.message}" }
    end

    def size : Int64
      with_circuit_breaker do
        Retry.with_retry_if(
          ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
          Session.config.retry_config
        ) do
          with_redis_connection { |client| RedisUtils.count_keys(client, prefixed("*")) }
        end
      end
    rescue ex : CircuitOpenException
      Log.warn { "Circuit breaker open while getting session count: #{ex.message}" }
      0_i64
    rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
      Log.warn { "Redis connection error while getting session count: #{ex.message}" }
      0_i64
    rescue ex : Exception
      Log.warn { "Unexpected error while getting session count: #{ex.message}" }
      0_i64
    end

    def clear : Nil
      with_circuit_breaker do
        Retry.with_retry_if(
          ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
          Session.config.retry_config
        ) do
          with_redis_connection { |client| RedisUtils.delete_keys(client, prefixed("*")) }
        end
      end
    rescue ex : CircuitOpenException
      Log.warn { "Circuit breaker open while clearing sessions: #{ex.message}" }
      # Don't raise on clear failures
    rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
      Log.warn { "Redis connection error while clearing sessions: #{ex.message}" }
      # Don't raise on clear failures
    rescue ex : Exception
      Log.warn { "Unexpected error while clearing sessions: #{ex.message}" }
    end

    # Health check method for monitoring
    def healthy? : Bool
      with_redis_connection(&.ping)
      true
    rescue ex : Exception
      Log.warn { "Redis health check failed: #{ex.message}" }
      false
    end

    # Graceful shutdown
    def shutdown
      if pool = @pool
        pool.shutdown
      elsif client = @client
        client.close
      end
    rescue ex : Exception
      Log.warn { "Error during Redis shutdown: #{ex.message}" }
    end

    # QueryableStore implementation

    def each_session(&block : T -> Nil) : Nil
      with_circuit_breaker do
        with_redis_connection do |client|
          RedisUtils.scan_keys(client, prefixed("*")) do |key_str|
            session_key = key_str.sub("session:", "")
            if session = self[session_key]?
              yield session
            end
          end
        end
      end
    rescue ex : CircuitOpenException | Redis::ConnectionError | Redis::CommandTimeoutError
      Log.warn { "Error while iterating sessions: #{ex.message}" }
    rescue ex : Exception
      Log.warn { "Unexpected error while iterating sessions: #{ex.message}" }
    end

    def bulk_delete(&predicate : T -> Bool) : Int64
      count = 0_i64
      keys_to_delete = [] of String

      with_circuit_breaker do
        with_redis_connection do |client|
          RedisUtils.scan_keys(client, prefixed("*")) do |key_str|
            session_key = key_str.sub("session:", "")
            if session = self[session_key]?
              if predicate.call(session)
                keys_to_delete << key_str

                # Delete in batches
                if keys_to_delete.size >= 100
                  client.del(keys_to_delete)
                  count += keys_to_delete.size.to_i64
                  keys_to_delete.clear
                end
              end
            end
          end

          # Delete remaining keys
          unless keys_to_delete.empty?
            client.del(keys_to_delete)
            count += keys_to_delete.size.to_i64
          end
        end
      end

      count
    rescue ex : CircuitOpenException | Redis::ConnectionError | Redis::CommandTimeoutError
      Log.warn { "Error while bulk deleting sessions: #{ex.message}" }
      count.as(Int64)
    rescue ex : Exception
      Log.warn { "Unexpected error while bulk deleting sessions: #{ex.message}" }
      count.as(Int64)
    end

    def all_session_ids : Array(String)
      ids = [] of String

      with_circuit_breaker do
        with_redis_connection do |client|
          RedisUtils.scan_keys(client, prefixed("*")) do |key_str|
            ids << key_str.sub("session:", "")
          end
        end
      end

      ids
    rescue ex : CircuitOpenException | Redis::ConnectionError | Redis::CommandTimeoutError
      Log.warn { "Error while getting session IDs: #{ex.message}" }
      [] of String
    rescue ex : Exception
      Log.warn { "Unexpected error while getting session IDs: #{ex.message}" }
      [] of String
    end

    private def prefixed(key : String) : String
      "session:#{key}"
    end

    # Execute a block with circuit breaker protection (if enabled)
    private def with_circuit_breaker(&block : -> T) : T forall T
      if cb = @circuit_breaker
        cb.call { yield }
      else
        yield
      end
    end

    # Execute a block with a Redis connection (either direct or from pool)
    private def with_redis_connection(&block : Redis -> T) : T forall T
      if pool = @pool
        pool.with_connection { |conn| yield conn }
      elsif client = @client
        yield client
      else
        raise "RedisStore not properly initialized: no client or pool available"
      end
    end

    private def encrypt_if_enabled(data : String) : String
      # First compress if enabled
      processed = Compression.compress_if_enabled(data)

      # Then encrypt if enabled
      return processed unless Session.config.encrypt_redis_data

      begin
        Session.config.encryptor.encrypt_and_sign(processed)
      rescue ex : Exception
        Log.error { "Redis data encryption failed: #{ex.message}" }
        raise SessionEncryptionException.new("Failed to encrypt session data for Redis", ex)
      end
    end

    private def decrypt_if_enabled(data : String) : String
      processed = data

      # First decrypt if enabled
      if Session.config.encrypt_redis_data
        begin
          processed = String.new(Session.config.encryptor.verify_and_decrypt(data))
        rescue ex : Exception
          Log.error { "Redis data decryption failed: #{ex.message}" }
          raise SessionEncryptionException.new("Failed to decrypt session data from Redis", ex)
        end
      end

      # Then decompress if needed
      Compression.decompress_if_needed(processed)
    end
  end

  # Backward-compatible wrapper for RedisStore with connection pooling
  #
  # DEPRECATED: Use RedisStore.with_pool(pool) or RedisStore.new(pool: pool) instead
  # This class is maintained for backward compatibility and will be removed in a future version
  #
  # Example migration:
  #   # Old way
  #   store = PooledRedisStore(UserSession).new(pool_config)
  #
  #   # New way
  #   store = RedisStore(UserSession).with_pool(pool_config)
  #   # or
  #   pool = ConnectionPool.new(pool_config)
  #   store = RedisStore(UserSession).new(pool: pool)
  class PooledRedisStore(T) < RedisStore(T)
    def initialize(pool : ConnectionPool)
      super(pool: pool)
    end

    def self.new(config : ConnectionPoolConfig = ConnectionPoolConfig.new)
      pool = ConnectionPool.new(config)
      new(pool)
    end
  end
end
