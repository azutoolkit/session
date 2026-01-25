require "spec"
require "../src/session"

REDIS_HOST = ENV["REDIS_HOST"]? || "localhost"

# Try to connect to Redis, but don't fail if it's not available
REDIS_AVAILABLE = begin
  client = Redis.new(host: REDIS_HOST)
  client.ping
  client.close
  true
rescue
  false
end

def redis_client
  Redis.new(host: REDIS_HOST)
end

class UserSession
  include Session::SessionData
  property? authenticated : Bool = true
  property username : String? = "example"
end

# Reset configuration to defaults before each test
def reset_config
  Session.config.timeout = 1.hour
  Session.config.secret = Session::Configuration::DEFAULT_SECRET
  Session.config.require_secure_secret = false
  Session.config.digest_algorithm = :sha256
  Session.config.digest_fallback = true
  Session.config.use_kdf = false
  Session.config.kdf_iterations = 100_000
  Session.config.encrypt_redis_data = false
  Session.config.circuit_breaker_enabled = false
  Session.config.sliding_expiration = false
  Session.config.compress_data = false
  Session.config.bind_to_ip = false
  Session.config.bind_to_user_agent = false
  Session.config.metrics_backend = Session::Metrics::NullBackend.new
  Session.config.cluster = Session::ClusterConfig.new
end

Spec.before_each do
  reset_config
end
