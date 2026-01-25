module Session
  class SessionHandler
    include HTTP::Handler

    def initialize(@session : Session::Provider)
    end

    def call(context : HTTP::Server::Context)
      load_session(context)
      call_next(context)
      save_session(context)
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

    private def validate_session_binding(request : HTTP::Request)
      # Get stored fingerprint from session data if available
      # Note: This requires the session data type to have a client_fingerprint property
      # For now, we create a new fingerprint and validate against request
      # In a full implementation, the fingerprint would be stored in the session
      _fingerprint = ClientFingerprint.from_request(request)

      # If session has a stored fingerprint, validate it
      # This is a simplified implementation - in practice you'd store the fingerprint
      # in the session data when the session is created
    end

    private def generate_session_id
      UUID.random.to_s
    end
  end
end
