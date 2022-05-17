require "redis"

module Session
  class InvalidSessionExeception < Exception
  end

  class RedisStore(T)
    include Store(T)
    include Provider

    def initialize(@client : Redis)
    end

    # Gets the session manager store type
    def storage : String
      self.class.name
    end

    def [](key : String) : SessionId(T)
      if data = @client.get prefixed(key)
        SessionId(T).from_json data
      else
        raise InvalidSessionExeception.new
      end
    end

    def []?(key : String) : SessionId(T)?
      if data = @client.get prefixed(key)
        SessionId(T).from_json data
      end
    end

    def set(key : String, session : SessionId(T)) : SessionId(T)
      @client.setex prefixed(key), timeout.total_seconds.to_i, session.to_json
      session
    end

    def delete(key : String)
      @client.del prefixed(key)
    end

    def size : Int64
      @client.keys(prefixed("*")).size.to_i64
    end

    def clear
      @client.keys(prefixed("*")).each { |k| @client.del k }
    end
  end
end
