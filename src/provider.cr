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

    def on(event : Symbol, *args)
      case event
      when :started then Session.config.on_started.call *args
      when :deleted then Session.config.on_deleted.call *args
      else               raise "InvalidSessionEventException"
      end
    end
  end
end
