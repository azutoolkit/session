module Session
  class MemoryStore(T) < Store(T)
    include Enumerable(SessionId(T))
    include QueryableStore(T)
    getter sessions : Hash(String, SessionId(T))
    property current_session : SessionId(T) = SessionId(T).new

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
      if session = sessions[key]?
        if session.valid?
          session
        else
          # Clean up expired session
          sessions.delete(key)
          raise SessionExpiredException.new("Session has expired: #{key}")
        end
      else
        raise SessionNotFoundException.new("Session not found: #{key}")
      end
    rescue ex : Session::SessionExpiredException | Session::SessionNotFoundException
      raise ex
    rescue ex : Exception
      Log.error { "Unexpected error while retrieving session #{key}: #{ex.message}" }
      raise SessionValidationException.new("Session retrieval failed", ex)
    end

    def []?(key : String) : SessionId(T)?
      if session = sessions[key]?
        if session.valid?
          session
        else
          # Clean up expired session
          sessions.delete(key)
          nil
        end
      end
    rescue ex : Exception
      Log.warn { "Error while retrieving session #{key}: #{ex.message}" }
      nil
    end

    def []=(key : String, session : SessionId(T)) : SessionId(T)
      # Validate session before storing
      unless session.valid?
        raise SessionValidationException.new("Cannot store expired session: #{key}")
      end

      sessions[key] = session
      session
    rescue ex : Session::SessionValidationException
      raise ex
    rescue ex : Exception
      Log.error { "Failed to store session #{key}: #{ex.message}" }
      raise SessionValidationException.new("Session storage failed", ex)
    end

    def delete(key : String)
      sessions.delete(key)
    rescue ex : Exception
      Log.warn { "Error while deleting session #{key}: #{ex.message}" }
    end

    def size : Int64
      # Only count valid sessions
      sessions.count { |_, session| session.valid? }.to_i64
    rescue ex : Exception
      Log.warn { "Error while counting sessions: #{ex.message}" }
      0_i64
    end

    def clear
      sessions.clear
    rescue ex : Exception
      Log.warn { "Error while clearing sessions: #{ex.message}" }
    end

    # Clean up expired sessions
    def cleanup_expired
      expired_keys = sessions.select { |_, session| !session.valid? }.keys
      expired_keys.each { |key| sessions.delete(key) }
      expired_keys.size
    rescue ex : Exception
      Log.warn { "Error while cleaning up expired sessions: #{ex.message}" }
      0
    end

    # Get memory usage statistics
    def memory_stats
      {
        total_sessions:   sessions.size,
        valid_sessions:   sessions.count { |_, session| session.valid? },
        expired_sessions: sessions.count { |_, session| !session.valid? },
      }
    rescue ex : Exception
      Log.warn { "Error while getting memory stats: #{ex.message}" }
      {total_sessions: 0, valid_sessions: 0, expired_sessions: 0}
    end

    # QueryableStore implementation

    def each_session(&block : SessionId(T) -> Nil) : Nil
      sessions.each_value do |session|
        yield session if session.valid?
      end
    rescue ex : Exception
      Log.warn { "Error while iterating sessions: #{ex.message}" }
    end

    def bulk_delete(&predicate : SessionId(T) -> Bool) : Int64
      count = 0_i64
      keys_to_delete = [] of String

      sessions.each do |key, session|
        if predicate.call(session)
          keys_to_delete << key
        end
      end

      keys_to_delete.each do |key|
        sessions.delete(key)
        count += 1
      end

      count
    rescue ex : Exception
      Log.warn { "Error while bulk deleting sessions: #{ex.message}" }
      0_i64
    end

    def all_session_ids : Array(String)
      sessions.select { |_, session| session.valid? }.keys
    rescue ex : Exception
      Log.warn { "Error while getting session IDs: #{ex.message}" }
      [] of String
    end
  end
end
