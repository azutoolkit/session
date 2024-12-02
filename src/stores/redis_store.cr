require "redis"

module Session
  class RedisStore(T) < Store(T)
    def initialize(@client : Redis = Redis.new)
    end

    def storage : String
      self.class.name
    end

    def [](key : String) : SessionId(T)
      if data = @client.get(prefixed(key))
        SessionId(T).from_json(data)
      else
        raise InvalidSessionExeception.new
      end
    end

    def []?(key : String) : SessionId(T)?
      if data = @client.get(prefixed(key))
        SessionId(T).from_json(data)
      end
    end

    def []=(key : String, session : SessionId(T)) : SessionId(T)
      @client.setex(prefixed(key), timeout.total_seconds.to_i, session.to_json)
      session
    end

    def delete(key : String)
      @client.del(prefixed(key))
    end

    def size : Int64
      @client.keys(prefixed("*")).size.to_i64
    end

    def clear
      keys = @client.keys(prefixed("*"))
      @client.del(keys) unless keys.empty?
    end

    private def prefixed(key : String) : String
      "session:#{key}"
    end
  end
end
