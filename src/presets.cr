module Session
  # Configuration presets for common deployment scenarios
  # Provides sensible defaults to reduce configuration complexity
  module Presets
    # Development preset - optimized for local development
    # - No secret validation required
    # - No encryption
    # - Short session timeout
    # - Verbose logging
    def self.development : Configuration
      Configuration.new.tap do |config|
        config.timeout = 30.minutes
        config.require_secure_secret = false
        config.encrypt_redis_data = false
        config.sliding_expiration = true
        config.log_errors = true
        config.circuit_breaker_enabled = false
        config.enable_retry = false
        config.compress_data = false
        config.bind_to_ip = false
        config.bind_to_user_agent = false
      end
    end

    # Production preset - balanced security and performance
    # - Requires secure secret
    # - Encrypted Redis data
    # - Standard timeout (1 hour)
    # - Circuit breaker enabled
    # - Retry enabled with conservative settings
    def self.production : Configuration
      Configuration.new.tap do |config|
        config.timeout = 1.hour
        config.require_secure_secret = true
        config.encrypt_redis_data = true
        config.sliding_expiration = true
        config.log_errors = true
        config.circuit_breaker_enabled = true
        config.enable_retry = true
        config.compress_data = true
        config.compression_threshold = 256
        config.bind_to_ip = false
        config.bind_to_user_agent = false
        config.use_kdf = true
        config.digest_algorithm = :sha256
      end
    end

    # High security preset - maximum security settings
    # - Requires secure secret
    # - Encrypted Redis data with KDF
    # - Client binding (IP + User-Agent)
    # - Short timeout with sliding expiration
    # - Fail fast on corruption
    def self.high_security : Configuration
      Configuration.new.tap do |config|
        config.timeout = 15.minutes
        config.require_secure_secret = true
        config.encrypt_redis_data = true
        config.sliding_expiration = true
        config.log_errors = true
        config.circuit_breaker_enabled = true
        config.enable_retry = true
        config.compress_data = true
        config.compression_threshold = 256
        config.bind_to_ip = true
        config.bind_to_user_agent = true
        config.use_kdf = true
        config.kdf_iterations = 100_000
        config.digest_algorithm = :sha256
        config.digest_fallback = false
        config.fail_fast_on_corruption = true
      end
    end

    # Testing preset - optimized for test suites
    # - Very short timeout
    # - No security requirements
    # - Minimal features enabled
    # - Fast and simple
    def self.testing : Configuration
      Configuration.new.tap do |config|
        config.timeout = 5.minutes
        config.require_secure_secret = false
        config.encrypt_redis_data = false
        config.sliding_expiration = false
        config.log_errors = false
        config.circuit_breaker_enabled = false
        config.enable_retry = false
        config.compress_data = false
        config.bind_to_ip = false
        config.bind_to_user_agent = false
      end
    end

    # Clustered preset - for multi-node deployments
    # Based on production preset with clustering enabled
    def self.clustered : Configuration
      production.tap do |config|
        config.cluster.enabled = true
        config.cluster.local_cache_enabled = true
        config.cluster.local_cache_ttl = 30.seconds
        config.cluster.local_cache_max_size = 10_000
      end
    end
  end
end
