module Session
  class SessionId(T)
    include JSON::Serializable

    getter session_id : String = UUID.random.to_s
    getter created_at : Time = Time.local

    property data : T
    getter expires_at : Time

    def initialize
      @expires_at = timeout
      @data = T.new
    end

    def expired?
      created_at > expires_at
    end

    def valid?
      !expired?
    end

    def ==(other : SessionId(T))
      session_id == other.session_id
    end

    private def timeout
      Session.config.timeout.from_now
    end
  end
end
