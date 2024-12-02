module Session
  module Provider
    abstract def storage : String

    macro included
      @mutex : Mutex = Mutex.new
      @current_session : SessionId(T) = SessionId(T).new

      def current_session : SessionId(T)
        @current_session
      end

      def session_id : String
        @current_session.session_id
      end

      def valid? : Bool
        @current_session.valid?
      end

      def data
        @current_session.data
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
        @current_session = SessionId(T).new
      end

      def create : SessionId(T)
        @current_session = SessionId(T).new
        self[session_id] = @current_session
        @current_session
      ensure
        on(:started, session_id, current_session.data)
      end

      def load_from(request_cookies : HTTP::Cookies) : SessionId(T)?
        if self.is_a?(CookieStore(T))
          self.cookies = request_cookies
        end

        if current_session_id = request_cookies[session_key]?
          if session = self[current_session_id.value]?
            @current_session = session
            on(:loaded, session_id, data)
          end
        end
      end

      def set_cookies(response_cookies : HTTP::Cookies, host : String = "") : Nil
        response_cookies << create_session_cookie(host) unless response_cookies[session_id]?
        if self.is_a?(CookieStore(T))
          response_cookies << self.create_data_cookie(@current_session, host)
        end
      ensure
        self[session_id] = @current_session
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
