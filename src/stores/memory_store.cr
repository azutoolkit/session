module Session
  class MemoryStore(T) < Store(T)
    include Enumerable(SessionId(T))
    getter sessions : Hash(String, SessionId(T))

    def initialize(@sessions : Hash(String, SessionId(T)) = Hash(String, SessionId(T)).new)
    end

    def each(&block : SessionId(T) -> _)
      sessions.each_value do |session|
        yield session if session.valid?
      end
    end

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
      sessions.size.to_i64
    end

    def clear
      sessions.clear
    end
  end
end
