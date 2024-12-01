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
        @current_session = if store_session = self[cookie.not_nil!.value]?
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
        on :deleted, session_id, current_session.data
      end

      # Sets the session cookie and the session data cookie
      # if not exists creates a new one
      def set_cookies(response_cookies : HTTP::Cookies, host : String = "")
        set_session_id_cookie(response_cookies, host)
        set_data_cookie(response_cookies, host: host)
      ensure
        on(:client, session_id, data)
      end

      def set_data_cookie(response_cookies : HTTP::Cookies, host : String = "", cookie_name : String = "_data_")
        cookie_name = "#{prefixed(session_id)}.#{cookie_name}"

        if data_cookie = response_cookies[cookie_name]?
          data_cookie.value = encrypt_and_sign(current_session.to_json)
          data_cookie.expires = timeout.from_now
          response_cookies << data_cookie
        else
          response_cookies << create_data_cookie(cookie_name, host)
        end
      end

      def create_data_cookie(cookie_name : String = "", host : String = "")
        HTTP::Cookie.new(
          name: cookie_name,
          value: encrypt_and_sign(current_session.to_json),
          expires: timeout.from_now,
          secure: true,
          domain: host,
          path: "/",
          samesite: HTTP::Cookie::SameSite::Strict,
          http_only: true,
          creation_time: Time.local,
        )
      end

      def set_session_id_cookie(response_cookies : HTTP::Cookies, host : String = "")
        cookie = response_cookies[session_id]? || cookie(host)
        response_cookies << cookie(host)
      end

      # Creates the session cookie
      def cookie(host : String)
        HTTP::Cookie.new(
          name: session_key,
          value: session_id,
          expires: timeout.from_now,
          secure: true,
          http_only: true,
          domain: host,
          path: "/",
          samesite: HTTP::Cookie::SameSite::Strict,
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
