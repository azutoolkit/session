module Session
  class SessionId(T)
    include JSON::Serializable

    getter session_id : String = UUID.random.to_s
    getter created_at : Time = Time.local

    @[JSON::Field(ignore: true)]
    getter expires : Time::Span?

    property data : T? = nil
    getter expires_at : Time

    def initialize(@expires = nil)
      @expires_at = @expires.not_nil!.from_now
    end

    def expired?
      created_at > expires_at.not_nil!
    end

    def valid?
      !expired?
    end

    def ==(other : SessionId(T))
      session_id == other.session_id
    end
  end
end
