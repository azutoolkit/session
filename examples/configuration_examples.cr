require "../src/session"

# Example 1: Using Configuration Presets
# =======================================

# Development environment - minimal security, verbose logging
Session.configure do |config|
  # Load development preset
  config.apply_preset(:development)

  # Override specific settings
  config.secret = ENV["SESSION_SECRET"]? || Configuration::DEFAULT_SECRET
  config.timeout = 2.hours

  # Set your store
  config.store = Session::MemoryStore(UserSession).new
end

# Production environment - balanced security and performance
Session.configure do |config|
  # Load production preset
  config.apply_preset(:production)

  # Override with environment-specific values
  config.secret = ENV["SESSION_SECRET"]
  config.timeout = 4.hours

  # Use Redis in production
  redis = Redis.new(
    host: ENV["REDIS_HOST"]? || "localhost",
    port: ENV["REDIS_PORT"]?.try(&.to_i) || 6379
  )
  config.store = Session::RedisStore(UserSession).new(client: redis)
end

# High security environment - maximum security
Session.configure do |config|
  # Load high security preset
  config.apply_preset(:high_security)

  # Must provide secure secret
  config.secret = ENV.fetch("SESSION_SECRET")

  # Use Redis with connection pooling for better performance
  pool_config = Session::ConnectionPoolConfig.new(
    size: 10,
    timeout: 5.seconds,
    redis_host: ENV["REDIS_HOST"]? || "localhost",
    redis_port: ENV["REDIS_PORT"]?.try(&.to_i) || 6379
  )
  config.store = Session::RedisStore(UserSession).with_pool(pool_config)
end

# Testing environment - fast and simple
Session.configure do |config|
  # Load testing preset
  config.apply_preset(:testing)

  # Use memory store for tests
  config.store = Session::MemoryStore(UserSession).new
end

# Clustered environment - multi-node deployment
Session.configure do |config|
  # Load clustered preset (based on production)
  config.apply_preset(:clustered)

  # Configure cluster settings
  config.cluster.node_id = ENV["NODE_ID"]? || UUID.random.to_s
  config.cluster.channel = "session:cluster:#{ENV["ENVIRONMENT"]?}"

  # Must provide secure secret
  config.secret = ENV.fetch("SESSION_SECRET")

  # Use clustered Redis store
  redis = Redis.new(host: ENV["REDIS_HOST"]? || "localhost")
  cluster_config = Session::ClusterConfig.new(
    enabled: true,
    node_id: config.cluster.node_id,
    local_cache_ttl: 1.minute,
    local_cache_max_size: 50_000
  )
  config.store = Session::ClusteredRedisStore(UserSession).new(redis, cluster_config)
end

# Example 2: Manual Configuration (No Preset)
# ===========================================

Session.configure do |config|
  # Core settings
  config.timeout = 30.minutes
  config.session_key = "_app_session"
  config.secret = ENV.fetch("SESSION_SECRET")

  # Security settings
  config.require_secure_secret = true
  config.encrypt_redis_data = true
  config.use_kdf = true
  config.digest_algorithm = :sha256

  # Session binding
  config.bind_to_ip = false
  config.bind_to_user_agent = true

  # Performance settings
  config.compress_data = true
  config.compression_threshold = 512
  config.sliding_expiration = true

  # Resilience settings
  config.circuit_breaker_enabled = true
  config.enable_retry = true

  # Store
  config.store = Session::RedisStore(UserSession).new
end

# Example 3: Preset with Selective Overrides
# ==========================================

Session.configure do |config|
  # Start with production preset
  config.apply_preset(:production)

  # Override only what you need
  config.timeout = 8.hours            # Longer session for this app
  config.bind_to_user_agent = true    # Add user agent binding
  config.compression_threshold = 1024 # Larger threshold

  config.secret = ENV.fetch("SESSION_SECRET")
  config.store = Session::RedisStore(UserSession).new
end

# Example 4: Environment-Based Configuration
# ==========================================

Session.configure do |config|
  environment = ENV["ENVIRONMENT"]? || "development"

  case environment
  when "development"
    config.apply_preset(:development)
    config.store = Session::MemoryStore(UserSession).new
  when "test"
    config.apply_preset(:testing)
    config.store = Session::MemoryStore(UserSession).new
  when "staging"
    config.apply_preset(:production)
    config.secret = ENV.fetch("SESSION_SECRET")
    redis = Redis.new(host: ENV["REDIS_HOST"]?)
    config.store = Session::RedisStore(UserSession).new(client: redis)
  when "production"
    config.apply_preset(:high_security)
    config.secret = ENV.fetch("SESSION_SECRET")
    pool_config = Session::ConnectionPoolConfig.new(size: 20)
    config.store = Session::RedisStore(UserSession).with_pool(pool_config)
  else
    raise "Unknown environment: #{environment}"
  end
end

# Example Session Data Structure
# ==============================

class UserSession < Session::Base
  property user_id : Int64?
  property username : String?
  property email : String?
  property roles : Array(String) = [] of String
  property last_activity : Time = Time.utc

  def authenticated? : Bool
    !user_id.nil?
  end
end
