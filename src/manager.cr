module Session
  class Manager(T)
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

    # Gets or create a session
    def load_from(cookie : HTTP::Cookie) : SessionId(T)?
      @current_session = self[cookie.value]?
    end

    def session_id
      @current_session.not_nil!.session_id
    end

    def valid?
      current_session.not_nil!.valid?
    end

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

    # Deletes the session cookie and clears the store
    def [](id : String)
      @store[prefixed(id)]
    end

    def []?(id : String)
      @store[prefixed(id)]?
    end

    def create(data : T)
      @current_session = SessionId(T).new(@timeout).not_nil!
      @current_session.not_nil!.data = data
      @store.set prefixed(session_id), @current_session.not_nil!, timeout
    end

    private def prefixed(key)
      "#{@session_key}:#{key}"
    end
  end
end
