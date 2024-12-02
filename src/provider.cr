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
        self[@current_session.session_id] = @current_session
        @current_session
      ensure
        on :started, session_id, @current_session.data
      end

      # Loads the session from cookies
      def load_from(request_cookies : HTTP::Cookies) : SessionId(T)?
        self.cookies = request_cookies
        if current_session_id = request_cookies[session_key]?
          session = self[current_session_id.value]?
          @current_session = session if session
          on(:loaded, session_id, data)
        end
      end

      # Deletes the current session
      def delete
        self.delete(session_id)
        on :deleted, session_id, @current_session.data
        create
      end

      # Sets session cookies
      def set_cookies(response_cookies : HTTP::Cookies, host : String = "")
        response_cookies << session_id_cookie(host) unless response_cookies[session_id]?
        response_cookies << create_data_cookie(host: host) if self.is_a? CookieStore(T)
      ensure
        on(:client, session_id, data)
      end

      def create_data_cookie(host : String = "")
        HTTP::Cookie.new(
          name: data_key,
          value: encrypt_and_sign(@current_session.to_json),
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

      # Creates the session cookie
      def session_id_cookie(host : String)
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
        self[session_id] = @current_session
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

    def data_key
      "#{Session.config.session_key}._data_"
    end

    def encrypt_and_sign(value)
      Session.config.encryptor.encrypt_and_sign(value)
    end

    def verify_and_decrypt(value)
      Session.config.encryptor.verify_and_decrypt(value)
    end
  end
