module Session
  class Manager(T)
    include Provider
    getter current_session : SessionId(T) = SessionId(T).new
    forward_missing_to current_session.data.not_nil!

    def initialize(@store : Store(T) = MemoryStore(T).new)
    end

    def storage : String
      @store.storage
    end

    # Deletes the current session
    def delete
      @store.delete session_id
      @current_session = SessionId(T).new
    ensure
      Session.config.on_deleted.call session_id
    end

    # Creates the session cookie
    def cookie : HTTP::Cookie
      HTTP::Cookie.new(
        name: session_key,
        value: session_id,
        expires: timeout.from_now,
        secure: true,
        http_only: true,
        creation_time: Time.local,
      )
    end

    # Gets a session by Session Id, throws Key not found
    def [](id : String)
      @store[id]
    end

    # Gets a session by Session Id, or returns nil
    def []?(id : String)
      @store[id]?
    end

    # Clears all the sessions from store
    def clear
      @store.clear
    end

    # Loads the session from a HTTP::Cookie
    def load_from(cookie : HTTP::Cookie) : SessionId(T)?
      @current_session = if store_session = self[cookie.value]?
                           store_session
                         else
                           create
                         end
    end

    # Creates a new session for the given data
    # Data is generic
    def create
      @current_session = SessionId(T).new
      @current_session
    ensure
      Session.config.on_started.call session_id
    end

    def session_id
      @current_session.session_id
    end

    def valid?
      @current_session.valid?
    end
  end
end
