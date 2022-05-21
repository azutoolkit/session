module Session
  module Provider
    abstract def storage : String

    macro included
      getter current_session : SessionId(T) = SessionId(T).new

      def session_id
        @current_session.session_id
      end

      def valid?
        @current_session.valid?
      end

      def data
        @current_session.data
      end

      # Creates a new session for the given data
      # Data is generic
      def create
        @current_session = SessionId(T).new
        @current_session
      ensure
        on :started, session_id, current_session.data
      end

      # Loads the session from a HTTP::Cookie
      def load_from(request_cookies : HTTP::Cookies) : SessionId(T)?
        self.cookies = request_cookies if self.is_a? CookieStore(T)
        cookie = request_cookies[session_key]?
        return @current_session = create if cookie.nil?
        @current_session =  if store_session = self[cookie.not_nil!.value]?
                              store_session
                            else
                              create
                            end
      ensure
        on(:loaded, session_id, data)
      end

      # Deletes the current session
      def delete
        delete session_id
        @current_session = SessionId(T).new
      ensure
        on :started, session_id, current_session.data
      end

      def set_cookies(response_cookies : HTTP::Cookies)
        response_cookies << cookie
        if self.is_a? CookieStore(T)
          response_cookies << HTTP::Cookie.new(
            name: prefixed(self.cookie_name + session_id),
            value: encrypt_and_sign(current_session.to_json),
            expires: timeout.from_now,
            secure: true,
            http_only: true,
            creation_time: Time.local,
          )
        end
      ensure
        on(:client, session_id, data)
      end

      # Creates the session cookie
      def cookie
        HTTP::Cookie.new(
          name: session_key,
          value: session_id,
          expires: timeout.from_now,
          secure: true,
          http_only: true,
          creation_time: Time.local,
        )
      ensure
        self[session_id] = current_session
      end
    end

    def timeout
      Session.config.timeout
    end

    def session_key
      Session.config.session_key
    end

    def prefixed(session_id)
      "#{session_key}.#{session_id}"
    end

    def on(event : Symbol, *args)
      case event
      when :started then Session.config.on_started.call *args
      when :deleted then Session.config.on_deleted.call *args
      when :loaded  then Session.config.on_loaded.call *args
      when :client  then Session.config.on_client.call *args
      else               raise InvalidSessionEventException.new
      end
    end

    def encrypt_and_sign(value)
      Session.config.encryptor.encrypt_and_sign(value)
    end

    def verify_and_decrypt(value)
      Session.config.encryptor.verify_and_decrypt(value)
    end
  end
end
