module Session
  # Cluster configuration for multi-node deployments
  # Defined here to be available for Configuration class
  class ClusterConfig
    property enabled : Bool = false
    property node_id : String = UUID.random.to_s
    property channel : String = "session:cluster:invalidate"
    property local_cache_enabled : Bool = true
    property local_cache_ttl : Time::Span = 30.seconds
    property local_cache_max_size : Int32 = 10_000
    property subscribe_timeout : Time::Span = 5.seconds

    def initialize(
      @enabled : Bool = false,
      @node_id : String = UUID.random.to_s,
      @channel : String = "session:cluster:invalidate",
      @local_cache_enabled : Bool = true,
      @local_cache_ttl : Time::Span = 30.seconds,
      @local_cache_max_size : Int32 = 10_000,
      @subscribe_timeout : Time::Span = 5.seconds,
    )
    end
  end

  class Configuration
    DEFAULT_SECRET = "1sxc1aNxGHTTZKlK5cpCgufJAqGM4G13"

    property timeout : Time::Span = 1.hour
    property session_key : String = "_session"
    property secret : String = DEFAULT_SECRET

    # Cluster configuration for multi-node deployments with Redis Pub/Sub
    property cluster : ClusterConfig = ClusterConfig.new

    # Security: require a secure secret (non-default) - raises if default secret is used
    property require_secure_secret : Bool = false

    # Digest algorithm for HMAC signatures (:sha256 recommended, :sha1 for legacy)
    property digest_algorithm : Symbol = :sha256

    # Enable auto-fallback to SHA1 for migrating old sessions (logs deprecation warning)
    property digest_fallback : Bool = true

    # Key Derivation Function (KDF) settings
    # When enabled, derives cipher key from secret using PBKDF2-SHA256
    property use_kdf : Bool = false
    property kdf_iterations : Int32 = 100_000
    property kdf_salt : String = "session_kdf_salt"

    # Redis encryption: when enabled, session data stored in Redis is encrypted
    property encrypt_redis_data : Bool = false

    # Circuit breaker configuration for Redis connections
    property circuit_breaker_enabled : Bool = false
    property circuit_breaker_config : CircuitBreakerConfig = CircuitBreakerConfig.new(
      failure_threshold: 5,
      reset_timeout: 30.seconds,
      half_open_max_calls: 1
    )

    # Sliding expiration: when enabled, session timeout resets on each access
    property sliding_expiration : Bool = false

    # Metrics backend for observability (default: NullBackend discards all metrics)
    property metrics_backend : Metrics::Backend = Metrics::NullBackend.new

    # Data compression: when enabled, session data is compressed before storage
    property compress_data : Bool = false
    # Minimum size in bytes before compression is applied (smaller data may grow with compression)
    property compression_threshold : Int32 = 256

    # Session binding: bind sessions to client fingerprint for security
    property bind_to_ip : Bool = false
    property bind_to_user_agent : Bool = false

    # Track if secret warning has been logged to avoid spamming
    @secret_warning_logged : Bool = false
    property on_started : Proc(String, Session::SessionData, Nil) = ->(sid : String, data : Session::SessionData) do
      Log.debug { "Session started - SessionId: #{sid} Data: #{data}" }
    end
    property on_deleted : Proc(String, Session::SessionData, Nil) = ->(sid : String, data : Session::SessionData) do
      Log.debug { "Session deleted - SessionId: #{sid} Data: #{data}" }
    end
    property on_loaded : Proc(String, Session::SessionData, Nil) = ->(sid : String, data : Session::SessionData) do
      Log.debug { "Session loaded - SessionId: #{sid} Data: #{data}" }
    end
    property on_client : Proc(String, Session::SessionData, Nil) = ->(sid : String, data : Session::SessionData) do
      Log.debug { "Session accessed - SessionId: #{sid} Data: #{data}" }
    end
    property on_regenerated : Proc(String, String, Session::SessionData, Nil) = ->(old_sid : String, new_sid : String, data : Session::SessionData) do
      Log.debug { "Session regenerated - OldId: #{old_sid} NewId: #{new_sid} Data: #{data}" }
    end

    property provider : Provider? = nil

    # Retry configuration for resilient operations
    property retry_config : RetryConfig = RetryConfig.new(
      max_attempts: 3,
      base_delay: 100.milliseconds,
      max_delay: 5.seconds,
      backoff_multiplier: 2.0,
      jitter: 0.1
    )

    # Error handling configuration
    property enable_retry : Bool = true
    property log_errors : Bool = true
    property fail_fast_on_corruption : Bool = true

    def session
      provider || raise "Session provider not configured"
    end

    def encryptor
      validate_secret!
      Message::Encryptor.new(
        secret,
        digest: digest_algorithm,
        fallback_digest: digest_fallback ? :sha1 : nil,
        use_kdf: use_kdf,
        kdf_iterations: kdf_iterations,
        kdf_salt: kdf_salt
      )
    end

    # Check if the current secret is the insecure default
    def using_default_secret? : Bool
      secret == DEFAULT_SECRET
    end

    # Validate secret security - warns or raises based on configuration
    def validate_secret! : Nil
      return unless using_default_secret?

      if require_secure_secret
        raise InsecureSecretException.new(
          "Using default secret is not allowed when require_secure_secret is enabled. " \
          "Please configure a secure secret using Session.configure { |c| c.secret = \"your-secure-secret\" }"
        )
      end

      # Log warning only once to avoid spam
      unless @secret_warning_logged
        Log.warn {
          "SECURITY WARNING: Using default session secret. This is insecure for production. " \
          "Configure a secure secret: Session.configure { |c| c.secret = \"your-32-byte-secret\" }"
        }
        @secret_warning_logged = true
      end
    end
  end

  class InsecureSecretException < Exception
    def initialize(message : String = "Insecure session secret configuration", cause : Exception? = nil)
      super(message, cause)
    end
  end
end
