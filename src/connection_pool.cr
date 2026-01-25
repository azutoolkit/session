require "redis"

module Session
  # Configuration for connection pool
  class ConnectionPoolConfig
    property size : Int32 = 5
    property timeout : Time::Span = 5.seconds
    property redis_host : String = "localhost"
    property redis_port : Int32 = 6379
    property redis_database : Int32 = 0
    property redis_password : String? = nil

    def initialize(
      @size : Int32 = 5,
      @timeout : Time::Span = 5.seconds,
      @redis_host : String = "localhost",
      @redis_port : Int32 = 6379,
      @redis_database : Int32 = 0,
      @redis_password : String? = nil
    )
    end
  end

  # Exception raised when pool checkout times out
  class ConnectionPoolTimeoutException < Exception
    def initialize(timeout : Time::Span)
      super("Failed to acquire connection from pool within #{timeout.total_seconds} seconds")
    end
  end

  # Simple connection pool for Redis connections
  class ConnectionPool
    getter config : ConnectionPoolConfig
    getter size : Int32
    getter available : Int32

    @connections : Array(Redis)
    @available_connections : Channel(Redis)
    @mutex : Mutex = Mutex.new

    def initialize(@config : ConnectionPoolConfig = ConnectionPoolConfig.new)
      @size = @config.size
      @connections = [] of Redis
      @available_connections = Channel(Redis).new(@size)
      @available = @size

      # Pre-create all connections
      @size.times do
        conn = create_connection
        @connections << conn
        @available_connections.send(conn)
      end
    end

    # Execute a block with a pooled connection
    def with_connection(&block : Redis -> T) : T forall T
      conn = checkout
      begin
        yield conn
      ensure
        checkin(conn)
      end
    end

    # Check out a connection from the pool
    def checkout : Redis
      select
      when conn = @available_connections.receive
        @mutex.synchronize { @available -= 1 }
        conn
      when timeout(@config.timeout)
        raise ConnectionPoolTimeoutException.new(@config.timeout)
      end
    end

    # Return a connection to the pool
    def checkin(conn : Redis) : Nil
      @mutex.synchronize { @available += 1 }
      @available_connections.send(conn)
    end

    # Get pool statistics
    def stats : NamedTuple(size: Int32, available: Int32, in_use: Int32)
      @mutex.synchronize do
        {
          size:      @size,
          available: @available,
          in_use:    @size - @available,
        }
      end
    end

    # Close all connections and shutdown the pool
    def shutdown : Nil
      @size.times do
        select
        when conn = @available_connections.receive
          begin
            conn.close
          rescue ex : Exception
            Log.warn { "Error closing pooled connection: #{ex.message}" }
          end
        when timeout(1.second)
          break
        end
      end
      @available_connections.close
    end

    # Check if pool is healthy (at least one connection works)
    def healthy? : Bool
      with_connection do |conn|
        conn.ping
        true
      end
    rescue ex : Exception
      Log.warn { "Connection pool health check failed: #{ex.message}" }
      false
    end

    private def create_connection : Redis
      Redis.new(
        host: @config.redis_host,
        port: @config.redis_port,
        database: @config.redis_database,
        password: @config.redis_password
      )
    end
  end

  # Redis store that uses connection pooling
  class PooledRedisStore(T) < Store(T)
    include QueryableStore(T)

    getter pool : ConnectionPool
    getter circuit_breaker : CircuitBreaker?

    def initialize(@pool : ConnectionPool)
      if Session.config.circuit_breaker_enabled
        @circuit_breaker = CircuitBreaker.new(Session.config.circuit_breaker_config)
      end
    end

    def self.new(config : ConnectionPoolConfig = ConnectionPoolConfig.new)
      pool = ConnectionPool.new(config)
      new(pool)
    end

    def storage : String
      self.class.name
    end

    def [](key : String) : SessionId(T)
      with_circuit_breaker do
        @pool.with_connection do |client|
          Retry.with_retry_if(
            ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
            Session.config.retry_config
          ) do
            if data = client.get(prefixed(key))
              json_data = decrypt_if_enabled(data)
              SessionId(T).from_json(json_data)
            else
              raise SessionNotFoundException.new("Session not found: #{key}")
            end
          end
        end
      end
    rescue ex : CircuitOpenException
      raise StorageConnectionException.new("Redis circuit breaker open", ex)
    rescue ex : ConnectionPoolTimeoutException
      raise StorageConnectionException.new("Connection pool timeout", ex)
    rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
      raise StorageConnectionException.new("Redis connection failed", ex)
    rescue ex : Session::SessionNotFoundException
      raise ex
    rescue ex : Exception
      raise SessionValidationException.new("Session retrieval failed", ex)
    end

    def []?(key : String) : SessionId(T)?
      with_circuit_breaker do
        @pool.with_connection do |client|
          if data = client.get(prefixed(key))
            json_data = decrypt_if_enabled(data)
            SessionId(T).from_json(json_data)
          end
        end
      end
    rescue ex : Exception
      Log.warn { "Error retrieving session #{key}: #{ex.message}" }
      nil
    end

    def []=(key : String, session : SessionId(T)) : SessionId(T)
      with_circuit_breaker do
        @pool.with_connection do |client|
          session_json = session.to_json
          data_to_store = encrypt_if_enabled(session_json)
          client.setex(prefixed(key), timeout.total_seconds.to_i, data_to_store)
          session
        end
      end
    rescue ex : CircuitOpenException | ConnectionPoolTimeoutException
      raise StorageConnectionException.new("Connection failed", ex)
    rescue ex : Redis::ConnectionError | Redis::CommandTimeoutError
      raise StorageConnectionException.new("Redis connection failed", ex)
    rescue ex : Exception
      raise SessionValidationException.new("Session storage failed", ex)
    end

    def delete(key : String)
      @pool.with_connection do |client|
        client.del(prefixed(key))
      end
    rescue ex : Exception
      Log.warn { "Error deleting session #{key}: #{ex.message}" }
    end

    def size : Int64
      count = 0_i64
      @pool.with_connection do |client|
        cursor = "0"
        pattern = prefixed("*")

        loop do
          result = client.scan(cursor, match: pattern, count: 100)
          cursor = result[0].as(String)
          keys = result[1].as(Array(Redis::Value))
          count += keys.size.to_i64
          break if cursor == "0"
        end
      end
      count
    rescue ex : Exception
      Log.warn { "Error getting session count: #{ex.message}" }
      0_i64
    end

    def clear
      @pool.with_connection do |client|
        cursor = "0"
        pattern = prefixed("*")

        loop do
          result = client.scan(cursor, match: pattern, count: 100)
          cursor = result[0].as(String)
          keys = result[1].as(Array(Redis::Value))

          unless keys.empty?
            string_keys = keys.map(&.as(String))
            client.del(string_keys)
          end

          break if cursor == "0"
        end
      end
    rescue ex : Exception
      Log.warn { "Error clearing sessions: #{ex.message}" }
    end

    def healthy? : Bool
      @pool.healthy?
    end

    def shutdown
      @pool.shutdown
    end

    # QueryableStore implementation
    def each_session(&block : SessionId(T) -> Nil) : Nil
      @pool.with_connection do |client|
        cursor = "0"
        pattern = prefixed("*")

        loop do
          result = client.scan(cursor, match: pattern, count: 100)
          cursor = result[0].as(String)
          keys = result[1].as(Array(Redis::Value))

          keys.each do |key|
            key_str = key.as(String)
            session_key = key_str.sub("session:", "")
            if session = self[session_key]?
              yield session
            end
          end

          break if cursor == "0"
        end
      end
    rescue ex : Exception
      Log.warn { "Error iterating sessions: #{ex.message}" }
    end

    def bulk_delete(&predicate : SessionId(T) -> Bool) : Int64
      count = 0_i64

      @pool.with_connection do |client|
        cursor = "0"
        pattern = prefixed("*")

        loop do
          result = client.scan(cursor, match: pattern, count: 100)
          cursor = result[0].as(String)
          keys = result[1].as(Array(Redis::Value))
          keys_to_delete = [] of String

          keys.each do |key|
            key_str = key.as(String)
            session_key = key_str.sub("session:", "")
            if session = self[session_key]?
              if predicate.call(session)
                keys_to_delete << key_str
              end
            end
          end

          unless keys_to_delete.empty?
            client.del(keys_to_delete)
            count += keys_to_delete.size.to_i64
          end

          break if cursor == "0"
        end
      end

      count
    rescue ex : Exception
      Log.warn { "Error bulk deleting sessions: #{ex.message}" }
      count
    end

    def all_session_ids : Array(String)
      ids = [] of String

      @pool.with_connection do |client|
        cursor = "0"
        pattern = prefixed("*")

        loop do
          result = client.scan(cursor, match: pattern, count: 100)
          cursor = result[0].as(String)
          keys = result[1].as(Array(Redis::Value))

          keys.each do |key|
            key_str = key.as(String)
            ids << key_str.sub("session:", "")
          end

          break if cursor == "0"
        end
      end

      ids
    rescue ex : Exception
      Log.warn { "Error getting session IDs: #{ex.message}" }
      [] of String
    end

    private def prefixed(key : String) : String
      "session:#{key}"
    end

    private def with_circuit_breaker(&block : -> T) : T forall T
      if cb = @circuit_breaker
        cb.call { yield }
      else
        yield
      end
    end

    private def encrypt_if_enabled(data : String) : String
      processed = Compression.compress_if_enabled(data)
      return processed unless Session.config.encrypt_redis_data

      Session.config.encryptor.encrypt_and_sign(processed)
    end

    private def decrypt_if_enabled(data : String) : String
      processed = data

      if Session.config.encrypt_redis_data
        processed = String.new(Session.config.encryptor.verify_and_decrypt(data))
      end

      Compression.decompress_if_needed(processed)
    end
  end
end
