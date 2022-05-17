module Session
  module Provider
    abstract def storage : String

    def timeout
      Session.config.timeout
    end

    def session_key
      Session.config.session_key
    end

    def prefixed(session_id)
      "#{session_key}:#{session_id}"
    end
  end
end
