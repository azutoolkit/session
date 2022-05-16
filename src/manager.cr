module Session
  module Provider
    abstract def storage : String
  end

  class Manager(T)
    include Provider

    getter current_session : SessionId(T)? = nil
    getter timeout : Time::Span
    getter session_key : String

    forward_missing_to current_session.not_nil!.data.not_nil!

    def initialize(
      @timeout = 1.hour,
      @session_key = "_session",
      @store : Store(T) = MemoryStore(T).new
    )
    end

    # Gets the session manager store type
    def storage : String
      @store.class.name
    end

    # Loads the session from a HTTP::Cookie
    def load_from(cookie : HTTP::Cookie) : SessionId(T)?
      @current_session = self[cookie.value]?
    end

    # Gets the current Session Id
    def session_id
      @current_session.not_nil!.session_id
    end

    # Deletes the current session
    def delete
      @store.delete prefixed(session_id)
      @current_session = nil
    end

    # Validates the current session has not expired
    def valid?
      current_session.not_nil!.valid?
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
      @store[prefixed(id)]
    end

    # Gets a session by Session Id, or returns nil
    def []?(id : String)
      @store[prefixed(id)]?
    end

    # Creates a new session for the given data
    # Data is generic
    def create(data : T)
      @current_session = SessionId(T).new(@timeout).not_nil!
      @current_session.not_nil!.data = data
      @store.set prefixed(session_id), @current_session.not_nil!, timeout
    end

    private def prefixed(session_id)
      "#{@session_key}:#{session_id}"
    end
  end
end
