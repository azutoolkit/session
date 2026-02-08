require "../store"

module Session
  class CookieStore(T) < Store(T)
    include Enumerable(HTTP::Cookie)
    property current_session : T = T.new
    property cookies

    def initialize(@cookies : HTTP::Cookies = HTTP::Cookies.new)
    end

    def each(&block : HTTP::Cookie -> _)
      cookies.each do |cookie|
        yield cookie if cookie.name.starts_with?(data_key)
      end
    end

    def storage : String
      self.class.name
    end

    def [](key : String) : T
      if data = cookies[data_key]?
        begin
          decrypted = String.new(verify_and_decrypt(data.value))
          payload = Compression.decompress_if_needed(decrypted)
          T.from_json payload
        rescue ex : Session::SessionEncryptionException
          Log.error { "Failed to decrypt session data: #{ex.message}" }
          raise SessionCorruptionException.new("Session data corruption detected", ex)
        rescue ex : JSON::ParseException
          Log.error { "Failed to parse session data: #{ex.message}" }
          raise SessionCorruptionException.new("Invalid session data format", ex)
        rescue ex : Exception
          Log.error { "Failed to deserialize session data: #{ex.message}" }
          raise SessionSerializationException.new("Session deserialization failed", ex)
        end
      else
        raise SessionNotFoundException.new("Session cookie not found")
      end
    rescue ex : Session::SessionCorruptionException | Session::SessionSerializationException | Session::SessionNotFoundException
      raise ex
    rescue ex : Exception
      Log.error { "Unexpected error while retrieving session: #{ex.message}" }
      raise SessionValidationException.new("Session retrieval failed", ex)
    end

    def []?(key : String) : T?
      if data = cookies[data_key]?
        begin
          decrypted = String.new(verify_and_decrypt(data.value))
          payload = Compression.decompress_if_needed(decrypted)
          T.from_json payload
        rescue ex : Session::SessionEncryptionException
          Log.warn { "Failed to decrypt session data: #{ex.message}" }
          nil
        rescue ex : JSON::ParseException
          Log.warn { "Failed to parse session data: #{ex.message}" }
          nil
        rescue ex : Exception
          Log.warn { "Failed to deserialize session data: #{ex.message}" }
          nil
        end
      end
    rescue ex : Exception
      Log.warn { "Error while retrieving session: #{ex.message}" }
      nil
    end

    def []=(key : String, session : T) : T
      # Validate session before storing
      unless session.valid?
        raise SessionValidationException.new("Cannot store expired session")
      end

      session_json = session.to_json
      compressed_data = Compression.compress_if_enabled(session_json)
      encrypted_data = encrypt_and_sign(compressed_data)

      # Validate cookie size before storing
      validate_cookie_size!(encrypted_data)

      cookies << HTTP::Cookie.new(
        name: data_key,
        value: encrypted_data,
        expires: timeout.from_now,
        secure: true,
        http_only: true,
        creation_time: Time.local,
      )
      session
    rescue ex : Session::SessionValidationException | Session::CookieSizeExceededException
      raise ex
    rescue ex : Session::SessionEncryptionException
      Log.error { "Failed to encrypt session data: #{ex.message}" }
      raise SessionEncryptionException.new("Session encryption failed", ex)
    rescue ex : JSON::ParseException
      Log.error { "Failed to serialize session data: #{ex.message}" }
      raise SessionSerializationException.new("Session serialization failed", ex)
    rescue ex : Exception
      Log.error { "Failed to store session: #{ex.message}" }
      raise SessionValidationException.new("Session storage failed", ex)
    end

    def delete(key : String)
      cookies.delete(data_key)
    rescue ex : Exception
      Log.warn { "Error while deleting session: #{ex.message}" }
    end

    def size : Int64
      cookies.count(&.name.starts_with?(data_key)).to_i64
    end

    def clear
      each { |cookie| cookies.delete(cookie.name) }
    rescue ex : Exception
      Log.warn { "Error while clearing sessions: #{ex.message}" }
    end

    def create_data_cookie(session : T, host : String = "") : HTTP::Cookie
      # Validate session before creating cookie
      unless session.valid?
        raise SessionValidationException.new("Cannot create cookie for expired session")
      end

      session_json = session.to_json
      compressed_data = Compression.compress_if_enabled(session_json)
      encrypted_data = encrypt_and_sign(compressed_data)

      # Validate cookie size before creating
      validate_cookie_size!(encrypted_data)

      HTTP::Cookie.new(
        name: data_key,
        value: encrypted_data,
        expires: timeout.from_now,
        secure: true,
        domain: host,
        path: "/",
        samesite: HTTP::Cookie::SameSite::Strict,
        http_only: true,
        creation_time: Time.local
      )
    rescue ex : Session::SessionValidationException | Session::CookieSizeExceededException
      raise ex
    rescue ex : Session::SessionEncryptionException
      Log.error { "Failed to encrypt session data for cookie: #{ex.message}" }
      raise SessionEncryptionException.new("Cookie encryption failed", ex)
    rescue ex : JSON::ParseException
      Log.error { "Failed to serialize session data for cookie: #{ex.message}" }
      raise SessionSerializationException.new("Cookie serialization failed", ex)
    rescue ex : Exception
      Log.error { "Failed to create session cookie: #{ex.message}" }
      raise SessionValidationException.new("Cookie creation failed", ex)
    end

    def data_key
      "#{Session.config.session_key}._data_"
    end

    private def encrypt_and_sign(value)
      Session.config.encryptor.encrypt_and_sign(value)
    rescue ex : Exception
      Log.error { "Encryption failed: #{ex.message}" }
      raise SessionEncryptionException.new("Session encryption failed", ex)
    end

    private def verify_and_decrypt(value)
      Session.config.encryptor.verify_and_decrypt(value)
    rescue ex : Exception
      Log.error { "Decryption failed: #{ex.message}" }
      raise SessionEncryptionException.new("Session decryption failed", ex)
    end

    private def validate_cookie_size!(encrypted_data : String) : Nil
      # Cookie size includes name, value, and overhead for attributes
      # The value is the largest part, so we check it against the limit
      cookie_size = data_key.bytesize + encrypted_data.bytesize + 100 # 100 bytes overhead for attributes
      max_size = CookieSizeExceededException::MAX_COOKIE_SIZE

      if cookie_size > max_size
        Log.error { "Cookie size #{cookie_size} bytes exceeds maximum #{max_size} bytes" }
        raise CookieSizeExceededException.new(cookie_size, max_size)
      end
    end
  end
end
