module Session
  class MemoryStore(T)
    include Store(T)
    include Provider

    getter sessions = {} of String => SessionId(T)

    # Gets the session manager store type
    def storage : String
      self.class.name
    end

    def [](key : String) : SessionId(T)
      sessions[key]
    end

    def []?(key : String) : SessionId(T)?
      sessions[key]?
    end

    def []=(key : String, session : SessionId(T)) : SessionId(T)
      sessions[key] = session
    end

    def delete(key : String)
      sessions.delete(key)
    end

    def size : Int64
      sessions.count { |_, v| v.valid? }.to_i64
    end

    def clear
      sessions.clear
    end
  end
end
