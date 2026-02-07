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
      @redis_password : String? = nil,
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

end
