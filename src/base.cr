module Session
  # Base class for session data
  #
  # Subclass this to define your session's data structure.
  # Override `authenticated?` to reflect your authentication logic.
  #
  # Example:
  #   ```
  # class UserSession < Session::Base
  #   property? authenticated : Bool = false
  #   property username : String? = nil
  #
  #   def authenticated? : Bool
  #     @authenticated
  #   end
  # end
  #   ```
  class Base
    include JSON::Serializable

    getter session_id : String = UUID.random.to_s
    getter created_at : Time = Time.local

    property expires_at : Time = Session.config.timeout.from_now

    def initialize
    end

    def authenticated? : Bool
      false
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

    def ==(other : Base)
      session_id == other.session_id
    end

    # Regenerate session identity in-place (new id, timestamps, expiry)
    protected def reset_identity! : Nil
      @session_id = UUID.random.to_s
      @created_at = Time.local
      @expires_at = timeout
    end

    private def timeout
      Session.config.timeout.from_now
    end
  end
end
