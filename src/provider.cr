module Session
  # Provider module for session lifecycle management
  # Included by Store(T) to provide session operations
  # The including class must define generic type parameter T where T : SessionData
  module Provider
    abstract def storage : String
    # Current session - type is determined by the generic parameter T of the including Store(T)
    abstract def current_session

    macro included
      @mutex : Mutex = Mutex.new
      @flash : Flash = Flash.new

      # Access flash messages
      def flash : Flash
        @flash
      end

      def session_id : String
        current_session.session_id
      end

      def valid? : Bool
        current_session.valid?
      end

      def data
        current_session.data
      end

      def timeout
        Session.config.timeout
      end

      def session_key
        Session.config.session_key
      end

      def delete
        delete(session_id)
        on(:deleted, session_id, data)
        self.current_session = SessionId(T).new
      end

      # Regenerate session ID while preserving session data
      # Important for security after authentication state changes
      def regenerate_id : SessionId(T)
        old_session_id = session_id
        old_data = current_session.data

        # Delete the old session
        delete(old_session_id)

        # Create a new session with the same data
        self.current_session = SessionId(T).new
        current_session.data = old_data

        # Store the new session
        self[session_id] = current_session

        # Trigger regeneration callback
        Session.config.on_regenerated.call(old_session_id, session_id, current_session.data)

        current_session
      end

      def create : SessionId(T)
        self.current_session = SessionId(T).new
        self[session_id] = current_session
        current_session
      ensure
        on(:started, session_id, current_session.data)
      end

      def load_from(request_cookies : HTTP::Cookies) : SessionId(T)?
        # Rotate flash messages at the start of each request
        @flash.rotate!

        if self.is_a?(CookieStore(T))
          self.cookies = request_cookies
        end

        if current_session_id = request_cookies[session_key]?
          if session = self[current_session_id.value]?
            self.current_session = session

            # Apply sliding expiration if enabled
            if Session.config.sliding_expiration
              current_session.touch
            end

            on(:loaded, session_id, data)
          end
        end
      end

      def set_cookies(response_cookies : HTTP::Cookies, host : String = "") : Nil
        response_cookies << create_session_cookie(host) unless response_cookies[session_id]?
        if self.is_a?(CookieStore(T))
          response_cookies << self.create_data_cookie(current_session, host)
        end
      ensure
        self[session_id] = current_session
        on(:client, session_id, data)
      end

      def on(event : Symbol, session_id : String, data : T)
        case event
        when :started then Session.config.on_started.call(session_id, data)
        when :loaded  then Session.config.on_loaded.call(session_id, data)
        when :client  then Session.config.on_client.call(session_id, data)
        when :deleted then Session.config.on_deleted.call(session_id, data)
        else
          raise "Unknown event: #{event}"
        end
      end

      def create_session_cookie(host : String) : HTTP::Cookie
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
      end
    end
  end
end
