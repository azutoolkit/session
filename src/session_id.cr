module Session
  # Container for session data with automatic expiration tracking
  #
  # Generic Constraint:
  #   T must include the SessionData module
  #   T must provide a parameterless constructor (T.new is called during initialization)
  class SessionId(T)
    include JSON::Serializable

    forward_missing_to data
    getter session_id : String = UUID.random.to_s
    getter created_at : Time = Time.local

    property data : T
    property expires_at : Time

    forward_missing_to data

    def initialize
      @expires_at = timeout
      @data = T.new
    end

    def expired?
      Time.local > expires_at
    end

    def valid?
      !expired?
    end

    # Extend the session expiration time (for sliding expiration)
    def touch : Nil
      @expires_at = timeout
    end

    # Get time remaining until session expires
    def time_until_expiry : Time::Span
      remaining = expires_at - Time.local
      remaining > Time::Span.zero ? remaining : Time::Span.zero
    end

    def ==(other : SessionId(T))
      session_id == other.session_id
    end

    private def timeout
      Session.config.timeout.from_now
    end
  end
end
