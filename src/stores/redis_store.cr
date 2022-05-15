require "redis"

module Session
  class InvalidSessionExeception < Exception
  end

  class RedisStore(T)
    include Store(T)

    def initialize(@client : Redis)
    end

    def [](key : String) : SessionId(T)
      if data = @client.get(key)
        SessionId(T).from_json data
      else
        raise InvalidSessionExeception.new
      end
    end

    def []?(key : String) : SessionId(T)?
      if data = @client.get(key)
        SessionId(T).from_json data
      end
    end

    def set(key : String, session : SessionId(T), expires : Time::Span) : SessionId(T)
      @client.setex(key, expires.total_seconds.to_i, session.to_json)
      session
    end

    def delete(key : String)
      @client.del(key)
    end

    def size : Int64
      0_i64
    end
  end
end
