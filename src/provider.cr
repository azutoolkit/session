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

      # Creates a new session
      def create
        @current_session = SessionId(T).new
        notify_event(:started)
        @current_session
      end

      # Loads the session from cookies
      def load_from(request_cookies : HTTP::Cookies) : SessionId(T)?
        self.cookies = request_cookies if self.is_a?(CookieStore(T))
        cookie = request_cookies[session_key]?
        @current_session = cookie ? fetch_session(cookie.value) : create
        notify_event(:loaded)
        @current_session
      end

      # Deletes the current session
      def delete
        remove_session(session_id)
        @current_session = SessionId(T).new
        notify_event(:deleted)
      end

      # Sets session cookies
      def set_cookies(response_cookies : HTTP::Cookies, host : String = "")
        set_session_id_cookie(response_cookies, host)
        set_data_cookie(response_cookies, host)
        notify_event(:client)
      end

      private

      # Fetches session data or creates a new session
      def fetch_session(cookie_value : String) : SessionId(T)
        self[cookie_value]? || create
      end

      # Removes session by key
      def remove_session(key : String)
        delete key
      end

      # Creates or updates the data cookie
      def set_data_cookie(response_cookies : HTTP::Cookies, host : String = "")
        cookie_name = "#{session_key}._data_"
        cookie = HTTP::Cookie.new(
          name: cookie_name,
          value: encrypt_and_sign(current_session.to_json),
          expires: timeout.from_now,
          secure: true,
          domain: host,
          path: "/",
          samesite: HTTP::Cookie::SameSite::Strict,
          http_only: true,
          creation_time: Time.local
        )
        response_cookies << cookie
      end

      # Creates or updates the session ID cookie
      def set_session_id_cookie(response_cookies : HTTP::Cookies, host : String = "")
        response_cookies << create_session_cookie(host)
      end

      # Creates the session ID cookie
      def create_session_cookie(host : String)
        HTTP::Cookie.new(
          name: session_key,
          value: session_id,
          expires: timeout.from_now,
          secure: true,
          http_only: true,
          domain: host,
          path: "/",
          samesite: HTTP::Cookie::SameSite::Strict,
          creation_time: Time.local
        )
      ensure
        self[session_id] = current_session
      end

      # Notify about session events
      def notify_event(event : Symbol)
        args = [session_id, current_session.data]
        Session.config.send("on_#{event}").call(*args) if Session.config.responds_to?("on_#{event}")
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

    def encrypt_and_sign(value)
      Session.config.encryptor.encrypt_and_sign(value)
    end

    def verify_and_decrypt(value)
      Session.config.encryptor.verify_and_decrypt(value)
    end
  end
