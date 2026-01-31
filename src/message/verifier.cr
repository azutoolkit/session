module Message
  class Verifier
    class InvalidSignatureError < Exception
    end

    # Track if fallback warning has been logged to avoid spam
    @@fallback_warning_logged : Bool = false

    def initialize(@secret : String, @digest : Symbol = :sha256, @fallback_digest : Symbol? = :sha1)
    end

    def valid_message?(data : String, digest : String) : Bool
      data.size > 0 && digest.size > 0 && Crypto::Subtle.constant_time_compare(digest, generate_digest(data))
    end

    # Check if message is valid with fallback digest (for migration)
    def valid_message_with_fallback?(data : String, digest : String) : Bool
      fallback = @fallback_digest
      return false if fallback.nil?
      data.size > 0 && digest.size > 0 && Crypto::Subtle.constant_time_compare(digest, generate_digest_with(data, fallback))
    end

    private def log_fallback_warning
      return if @@fallback_warning_logged
      Session::Log.warn {
        "DEPRECATION: Session verified using legacy #{@fallback_digest} digest. " \
        "Sessions will be re-signed with #{@digest} on next save. " \
        "Consider disabling fallback after migration: Session.configure { |c| c.digest_fallback = false }"
      }
      @@fallback_warning_logged = true
    end

    def verified(signed_message : String) : String?
      json_data = ::Base64.decode_string(signed_message)
      data, digest = Tuple(String, String).from_json(json_data)

      if valid_message?(data.to_s, digest.to_s)
        String.new(decode(data.to_s))
      elsif valid_message_with_fallback?(data.to_s, digest.to_s)
        log_fallback_warning
        String.new(decode(data.to_s))
      end
    rescue JSON::ParseException | Base64::Error
      begin
        data, digest = signed_message.split("--", 2)
      rescue IndexError
        return nil
      end

      if (data && digest).nil?
        return nil
      end

      if valid_message?(data.to_s, digest.to_s)
        String.new(decode(data.to_s))
      elsif valid_message_with_fallback?(data.to_s, digest.to_s)
        log_fallback_warning
        String.new(decode(data.to_s))
      end
    rescue ex : ArgumentError
      return if ex.message =~ %r{invalid base64}
      raise ex
    end

    def verify(signed_message : String) : String
      verified(signed_message) || raise InvalidSignatureError.new
    end

    def verify_raw(signed_message : String) : Bytes
      begin
        json_data = ::Base64.decode_string(signed_message)
        data, digest = Tuple(String, String).from_json(json_data)
      rescue JSON::ParseException | Base64::Error
        begin
          data, digest = signed_message.split("--", 2)
        rescue IndexError
          data, digest = nil, nil
        end
      end

      if (data && digest).nil?
        raise InvalidSignatureError.new
      end

      if valid_message?(data.to_s, digest.to_s)
        decode(data.to_s)
      elsif valid_message_with_fallback?(data.to_s, digest.to_s)
        log_fallback_warning
        decode(data.to_s)
      else
        raise InvalidSignatureError.new
      end
    end

    def generate(value : String | Bytes) : String
      data = encode(value)
      encode({data, generate_digest(data)}.to_json)
    end

    private def encode(data) : String
      ::Base64.urlsafe_encode(data)
    end

    private def decode(data) : Bytes
      ::Base64.decode(data)
    end

    private def generate_digest(data) : String
      generate_digest_with(data, @digest)
    end

    private def generate_digest_with(data, algorithm : Symbol) : String
      encode(OpenSSL::HMAC.digest(OpenSSL::Algorithm.parse(algorithm.to_s), @secret, data))
    end
  end
end
