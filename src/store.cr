module Session
  # Abstract base class for session storage backends
  #
  # Generic Constraint:
  #   T must inherit from Session::Base
  #   T must provide a parameterless constructor (T.new)
  #
  # Example usage:
  #   ```
  # class UserSession < Session::Base
  #   property? authenticated : Bool = false
  #   property user_id : Int64? = nil
  # end
  #
  # # Use memory store for development
  # store = Session::MemoryStore(UserSession).new
  #
  # # Use Redis for production
  # store = Session::RedisStore(UserSession).new(Redis.new)
  #   ```
  abstract class Store(T)
    # Storage abstraction - must be implemented by subclasses
    abstract def storage : String

    # Current session must be provided by subclasses
    # Typically implemented as: property current_session : T = T.new
    abstract def current_session : T
    abstract def current_session=(current_session : T)

    # Core store operations
    abstract def [](key : String) : T
    abstract def []?(key : String) : T?
    abstract def []=(key : String, session : T) : T
    abstract def delete(key : String)
    abstract def size : Int64
    abstract def clear

    # Instance variables for session lifecycle
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

    def timeout
      Session.config.timeout
    end

    def session_key
      Session.config.session_key
    end

    # Delete current session and create a new one
    def delete
      delete(session_id)
      on(:deleted, session_id, current_session)
      self.current_session = T.new
    end

    # Regenerate session ID while preserving session data
    # Important for security after authentication state changes
    def regenerate_id : T
      old_session_id = session_id

      # Delete the old session
      delete(old_session_id)

      # Regenerate identity in-place (preserves all user data)
      current_session.reset_identity!

      # Store the session with new ID
      self[session_id] = current_session

      # Trigger regeneration callback
      Session.config.on_regenerated.call(old_session_id, session_id, current_session)

      current_session
    end

    def create : T
      self.current_session = T.new
      self[session_id] = current_session
      current_session
    ensure
      on(:started, session_id, current_session)
    end

    def load_from(request_cookies : HTTP::Cookies) : T?
      # Rotate flash messages at the start of each request
      @flash.rotate!

      if self.is_a?(CookieStore(T))
        self.as(CookieStore(T)).cookies = request_cookies
      end

      if current_session_id = request_cookies[session_key]?
        if session = self[current_session_id.value]?
          self.current_session = session

          # Apply sliding expiration if enabled
          if Session.config.sliding_expiration
            current_session.touch
          end

          on(:loaded, session_id, current_session)
        end
      end
    end

    def set_cookies(response_cookies : HTTP::Cookies, host : String = "") : Nil
      response_cookies << create_session_cookie(host) unless response_cookies[session_id]?
      if self.is_a?(CookieStore(T))
        response_cookies << self.as(CookieStore(T)).create_data_cookie(current_session, host)
      end
    ensure
      self[session_id] = current_session
      on(:client, session_id, current_session)
    end

    def on(event : Symbol, session_id : String, session : T)
      case event
      when :started then Session.config.on_started.call(session_id, session)
      when :loaded  then Session.config.on_loaded.call(session_id, session)
      when :client  then Session.config.on_client.call(session_id, session)
      when :deleted then Session.config.on_deleted.call(session_id, session)
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

  # Module for stores that support querying sessions
  #
  # Generic Constraint:
  #   T must inherit from Session::Base
  #   This module should only be included by Store(T) subclasses
  module QueryableStore(T)
    # Iterate over all sessions matching a predicate
    abstract def each_session(&block : T -> Nil) : Nil

    # Find sessions matching a predicate
    def find_by(&predicate : T -> Bool) : Array(T)
      results = [] of T
      each_session do |session|
        results << session if predicate.call(session)
      end
      results
    end

    # Find first session matching a predicate
    def find_first(&predicate : T -> Bool) : T?
      result : T? = nil
      each_session do |session|
        if predicate.call(session)
          result = session
          break
        end
      end
      result
    end

    # Count sessions matching a predicate
    def count_by(&predicate : T -> Bool) : Int64
      count = 0_i64
      each_session do |session|
        count += 1 if predicate.call(session)
      end
      count
    end

    # Delete all sessions matching a predicate
    abstract def bulk_delete(&predicate : T -> Bool) : Int64

    # Get all session IDs
    abstract def all_session_ids : Array(String)
  end
end
