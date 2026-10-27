module Session
  class SessionHandler(T)
    include HTTP::Handler

    def initialize(@session : Store(T))
    end

    def call(context : HTTP::Server::Context)
      validate_secret!
      load_session(context)
      output = commit_before_first_write(context)
      call_next(context)
      persist_after_commit(output)
    ensure
      @session.release
    end

    # The session is saved as soon as the response starts, so its cookies still go out with it.
    # The response may be started by a fiber the handler spawned, which has no current session:
    # that fiber is given the request's session for the save, and forgets it again.
    private def commit_before_first_write(context : HTTP::Server::Context) : CommitOnWrite
      request_fiber = Fiber.current
      request_session = @session.current_session
      CommitOnWrite.new(context.response.output) do
        if Fiber.current == request_fiber
          save_session(context)
        else
          save_for_other_fiber(context, request_session)
        end
      end.tap { |output| context.response.output = output }
    end

    private def save_for_other_fiber(context : HTTP::Server::Context, session : T)
      @session.current_session = session
      save_session(context)
    ensure
      @session.release
    end

    # What the endpoint changed after the response started cannot reach the cookies any more
    # (headers are sent), but a server-side store still gets the final state.
    private def persist_after_commit(output : CommitOnWrite) : Nil
      already_sent = output.committed?
      output.commit
      return unless already_sent && !@session.is_a?(CookieStore(T))

      @session[@session.session_id] = @session.current_session
    rescue ex : Exception
      Log.warn { "Failed to save the session after the response started: #{ex.message}" }
    end

    # A store that encrypts with the secret cannot work without a usable one: fail the request
    # (`InsecureSecretException`, a 500) instead of answering it with a session that is never saved.
    private def validate_secret! : Nil
      return unless @session.is_a?(CookieStore(T)) || Session.config.encrypt_redis_data
      Session.config.validate_secret!
    end

    private def load_session(context : HTTP::Server::Context)
      @session.load_from(context.request.cookies)

      # Validate client binding if enabled and session exists
      if ClientFingerprint.binding_enabled? && @session.valid?
        validate_session_binding(context.request)
      end
    rescue ex : Session::SessionBindingException
      Log.warn { "Session binding failed for request #{context.request.resource}: #{ex.message}" }
      clear_corrupted_session(context)
    rescue ex : Session::SessionExpiredException
      Log.info { "Session expired for request #{context.request.resource}: #{ex.message}" }
    rescue ex : Session::SessionCorruptionException
      Log.warn { "Session corruption detected for request #{context.request.resource}: #{ex.message}" }
      clear_corrupted_session(context)
    rescue ex : Session::StorageConnectionException
      Log.error { "Storage connection error for request #{context.request.resource}: #{ex.message}" }
    rescue ex : Session::SessionValidationException
      Log.warn { "Session validation failed for request #{context.request.resource}: #{ex.message}" }
    rescue ex : Exception
      Log.warn { "Failed to load session from cookies: #{ex.message}" }
    end

    private def save_session(context : HTTP::Server::Context)
      @session.set_cookies(context.response.cookies, context.request.hostname.to_s)
    rescue ex : Session::SessionEncryptionException
      Log.error { "Failed to encrypt session cookies: #{ex.message}" }
    rescue ex : Session::SessionValidationException
      Log.warn { "Failed to validate session for cookies: #{ex.message}" }
    rescue ex : Exception
      Log.warn { "Failed to set session cookies: #{ex.message}" }
    end

    private def clear_corrupted_session(context : HTTP::Server::Context)
      # Clear any existing session cookies
      context.response.cookies.delete(@session.session_key)
      # Create a new session
      @session.create
    rescue ex : Exception
      Log.warn { "Failed to clear corrupted session: #{ex.message}" }
    end

    # A session is tied to the client it was first used from: a request from a different
    # client is refused (and answered with a fresh session by `load_session`'s rescue).
    private def validate_session_binding(request : HTTP::Request)
      session = @session.current_session

      if fingerprint = session.client_fingerprint
        fingerprint.validate!(request)
      else
        session.client_fingerprint = ClientFingerprint.from_request(request)
      end
    end

    private def generate_session_id
      UUID.random.to_s
    end
  end
end
