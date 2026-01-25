require "openssl"

module Session
  # Client fingerprint for session binding
  class ClientFingerprint
    include JSON::Serializable

    property ip_hash : String?
    property user_agent_hash : String?

    def initialize(@ip_hash : String? = nil, @user_agent_hash : String? = nil)
    end

    # Create fingerprint from request context
    def self.from_request(request : HTTP::Request) : ClientFingerprint
      fingerprint = new

      if Session.config.bind_to_ip
        if ip = extract_client_ip(request)
          fingerprint.ip_hash = hash_value(ip)
        end
      end

      if Session.config.bind_to_user_agent
        if ua = request.headers["User-Agent"]?
          fingerprint.user_agent_hash = hash_value(ua)
        end
      end

      fingerprint
    end

    # Validate fingerprint against current request
    def validate!(request : HTTP::Request) : Nil
      if Session.config.bind_to_ip && @ip_hash
        current_ip = ClientFingerprint.extract_client_ip(request)
        if current_ip.nil? || hash_value(current_ip) != @ip_hash
          raise SessionBindingException.new("ip", "Session IP address mismatch")
        end
      end

      if Session.config.bind_to_user_agent && @user_agent_hash
        current_ua = request.headers["User-Agent"]?
        if current_ua.nil? || hash_value(current_ua) != @user_agent_hash
          raise SessionBindingException.new("user_agent", "Session User-Agent mismatch")
        end
      end
    end

    # Check if binding is enabled
    def self.binding_enabled? : Bool
      Session.config.bind_to_ip || Session.config.bind_to_user_agent
    end

    # Check if fingerprint is empty (no binding set)
    def empty? : Bool
      @ip_hash.nil? && @user_agent_hash.nil?
    end

    # Extract client IP from request, considering proxy headers
    protected def self.extract_client_ip(request : HTTP::Request) : String?
      # Check X-Forwarded-For first (for proxied requests)
      if forwarded = request.headers["X-Forwarded-For"]?
        # Take the first IP (original client)
        return forwarded.split(",").first.strip
      end

      # Check X-Real-IP
      if real_ip = request.headers["X-Real-IP"]?
        return real_ip.strip
      end

      # Fall back to remote address (may not be available in all contexts)
      nil
    end

    private def hash_value(value : String) : String
      ClientFingerprint.hash_value(value)
    end

    protected def self.hash_value(value : String) : String
      OpenSSL::Digest.new("SHA256").update(value).final.hexstring
    end
  end
end
