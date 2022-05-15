module Session
  class MemoryStore(T)
    include Store(T)

    getter sessions = {} of String => SessionId(T)

    def [](key : String) : SessionId(T)
      sessions[key]
    end

    def []?(key : String) : SessionId(T)?
      sessions[key]?
    end

    def set(key : String, session : SessionId(T), expires : Time::Span) : SessionId(T)
      sessions[key] = session
    end

    def delete(key : String)
      sessions.delete(key)
    end

    def size : Int64
      sessions.count { |k, v| v.valid? }.to_i64
    end
  end
end
