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
    # The secret older releases signed with when none was configured. It is public, so it is never
    # used by default any more and is refused where `require_secure_secret` holds.
    DEFAULT_SECRET = "1sxc1aNxGHTTZKlK5cpCgufJAqGM4G13"

    property timeout : Time::Span = 1.hour
    property session_key : String = "_session"
    setter secret : String?

    # Cookie attributes. Cookies are always HttpOnly. Secure keeps them off plain http (browsers
    # still accept a Secure cookie over http on localhost); turn it off only for an http-only setup.
    property cookie_secure : Bool = true
    property cookie_same_site : HTTP::Cookie::SameSite = HTTP::Cookie::SameSite::Strict

    # Where a secure secret is required (production, staging), insecure cookies are refused too,
    # unless this opts out explicitly.
    property allow_insecure_cookies : Bool = false

    # Cluster configuration for multi-node deployments with Redis Pub/Sub
    property cluster : ClusterConfig = ClusterConfig.new

    # Environments that must not run on the published default secret.
    PRODUCTION_ENVIRONMENTS = %w(production staging)

    # Whether a missing or published secret is an error rather than a warning. Unless set, it holds
    # in production and staging, read from `CRYSTAL_ENV` (case-insensitive) each time it is checked.
    setter require_secure_secret : Bool?

    def require_secure_secret : Bool
      @require_secure_secret.nil? ? Configuration.production_environment? : @require_secure_secret == true
    end

    def self.production_environment? : Bool
      PRODUCTION_ENVIRONMENTS.includes?(ENV["CRYSTAL_ENV"]?.try(&.strip.downcase))
    end

    # The key sessions are encrypted and signed with: the one configured, else `SESSION_SECRET`.
    # Without either, `InsecureSecretException` where `require_secure_secret` holds, and otherwise a
    # random key for this process only (sessions do not survive a restart or reach another instance).
    # Not memoised: the random fallback is refused again as soon as `require_secure_secret` holds.
    def secret : String
      @secret || ENV["SESSION_SECRET"]?.presence || fallback_secret
    end

    # AES-256 takes a 32-byte key, and the secret is that key unless `use_kdf` derives one.
    MIN_SECRET_BYTES = 32

    private def fallback_secret : String
      if require_secure_secret
        raise InsecureSecretException.new(
          "SESSION_SECRET is not set: set it, or configure one with Session.configure { |c| c.secret = ... }"
        )
      end
      Configuration.process_secret
    end

    @@process_secret : String = Random::Secure.hex(32)
    @@process_secret_warned = Atomic(Bool).new(false)

    # The random fallback, one per process so every configuration agrees on it; warns once.
    def self.process_secret : String
      unless @@process_secret_warned.swap(true)
        Log.warn { "SESSION_SECRET is not set: using a random session secret for this process only" }
      end
      @@process_secret
    end

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

    # Whether `X-Forwarded-For` and `X-Real-IP` name the client for IP binding. Any client can
    # send them, so they are believed only when a trusted proxy in front of the app sets them.
    property trust_proxy_headers : Bool = false

    # Track if secret warning has been logged to avoid spamming
    @secret_warning_logged : Bool = false
    property on_started : Proc(String, Session::Base, Nil) = ->(sid : String, data : Session::Base) do
      Log.debug { "Session started - SessionId: #{sid} Data: #{data}" }
    end
    property on_deleted : Proc(String, Session::Base, Nil) = ->(sid : String, data : Session::Base) do
      Log.debug { "Session deleted - SessionId: #{sid} Data: #{data}" }
    end
    property on_loaded : Proc(String, Session::Base, Nil) = ->(sid : String, data : Session::Base) do
      Log.debug { "Session loaded - SessionId: #{sid} Data: #{data}" }
    end
    property on_client : Proc(String, Session::Base, Nil) = ->(sid : String, data : Session::Base) do
      Log.debug { "Session accessed - SessionId: #{sid} Data: #{data}" }
    end
    property on_regenerated : Proc(String, String, Session::Base, Nil) = ->(old_sid : String, new_sid : String, data : Session::Base) do
      Log.debug { "Session regenerated - OldId: #{old_sid} NewId: #{new_sid} Data: #{data}" }
    end

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

    # Load configuration from a preset (returns a new Configuration instance)
    # Available presets: :development, :production, :high_security, :testing, :clustered
    def self.from_preset(preset : Symbol) : Configuration
      resolve_preset(preset)
    end

    # Apply a preset's settings to this configuration instance
    # Available presets: :development, :production, :high_security, :testing, :clustered
    def apply_preset(preset : Symbol) : self
      source = Configuration.resolve_preset(preset)
      self.timeout = source.timeout
      self.require_secure_secret = source.require_secure_secret
      self.encrypt_redis_data = source.encrypt_redis_data
      self.sliding_expiration = source.sliding_expiration
      self.log_errors = source.log_errors
      self.circuit_breaker_enabled = source.circuit_breaker_enabled
      self.circuit_breaker_config = source.circuit_breaker_config
      self.enable_retry = source.enable_retry
      self.retry_config = source.retry_config
      self.compress_data = source.compress_data
      self.compression_threshold = source.compression_threshold
      self.bind_to_ip = source.bind_to_ip
      self.bind_to_user_agent = source.bind_to_user_agent
      self.use_kdf = source.use_kdf
      self.kdf_iterations = source.kdf_iterations
      self.digest_algorithm = source.digest_algorithm
      self.digest_fallback = source.digest_fallback
      self.fail_fast_on_corruption = source.fail_fast_on_corruption
      self.cluster = source.cluster
      self
    end

    protected def self.resolve_preset(preset : Symbol) : Configuration
      case preset
      when :development
        Presets.development
      when :production
        Presets.production
      when :high_security
        Presets.high_security
      when :testing
        Presets.testing
      when :clustered
        Presets.clustered
      else
        raise ArgumentError.new("Unknown preset: #{preset}. Available: :development, :production, :high_security, :testing, :clustered")
      end
    end

    # Raises `InvalidCookieOptions` for cookie options browsers reject or that defeat the secret requirement.
    def validate_cookie_options! : Nil
      return if cookie_secure

      if cookie_same_site.none?
        raise InvalidCookieOptions.new("SameSite=None cookies must be Secure: set cookie_secure = true or another cookie_same_site")
      end

      if require_secure_secret && !allow_insecure_cookies
        raise InvalidCookieOptions.new(
          "Insecure cookies (cookie_secure = false) are not allowed when require_secure_secret is enabled. " \
          "Set allow_insecure_cookies = true to opt out explicitly."
        )
      end
    end

    def session
      raise "Session store not configured. Call Session.use_store(StoreType) before Session.configure."
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
      key = secret
      if key.bytesize < MIN_SECRET_BYTES && !use_kdf
        raise InsecureSecretException.new(
          "The session secret is #{key.bytesize} bytes; it must be at least #{MIN_SECRET_BYTES} bytes " \
          "(generate one with `openssl rand -hex 32`)"
        )
      end
      return unless key == DEFAULT_SECRET

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

  class InvalidCookieOptions < Exception
    def initialize(message : String = "Invalid session cookie options", cause : Exception? = nil)
      super(message, cause)
    end
  end

  class InsecureSecretException < Exception
    def initialize(message : String = "Insecure session secret configuration", cause : Exception? = nil)
      super(message, cause)
    end
  end
end
