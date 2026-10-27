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

class UserSession < Session::Base
  property? authenticated : Bool = true
  property username : String? = "example"
end

Session.use_store(Session::MemoryStore(UserSession))

# Reset configuration to defaults before each test: every setting a preset or a spec changes
# goes back to the value a new `Session::Configuration` has.
def reset_config
  defaults = Session::Configuration.new
  config = Session.config
  config.store = Session::MemoryStore(UserSession).new
  config.timeout = defaults.timeout
  config.session_key = defaults.session_key
  config.secret = Session::Configuration::DEFAULT_SECRET
  config.require_secure_secret = false
  config.cookie_secure = defaults.cookie_secure
  config.cookie_same_site = defaults.cookie_same_site
  config.allow_insecure_cookies = defaults.allow_insecure_cookies
  config.digest_algorithm = defaults.digest_algorithm
  config.digest_fallback = defaults.digest_fallback
  config.use_kdf = defaults.use_kdf
  config.kdf_iterations = defaults.kdf_iterations
  config.kdf_salt = defaults.kdf_salt
  config.encrypt_redis_data = defaults.encrypt_redis_data
  config.circuit_breaker_enabled = defaults.circuit_breaker_enabled
  config.circuit_breaker_config = defaults.circuit_breaker_config
  config.sliding_expiration = defaults.sliding_expiration
  config.compress_data = defaults.compress_data
  config.compression_threshold = defaults.compression_threshold
  config.bind_to_ip = defaults.bind_to_ip
  config.bind_to_user_agent = defaults.bind_to_user_agent
  config.trust_proxy_headers = defaults.trust_proxy_headers
  config.enable_retry = defaults.enable_retry
  config.retry_config = defaults.retry_config
  config.log_errors = defaults.log_errors
  config.fail_fast_on_corruption = defaults.fail_fast_on_corruption
  config.metrics_backend = Session::Metrics::NullBackend.new
  config.cluster = Session::ClusterConfig.new
  config.on_started = defaults.on_started
  config.on_deleted = defaults.on_deleted
  config.on_loaded = defaults.on_loaded
  config.on_client = defaults.on_client
  config.on_regenerated = defaults.on_regenerated
end

Spec.before_each do
  reset_config
end

# Waits for something that happens in another fiber, such as a Pub/Sub message, to become true.
# Returns as soon as it does (so the usual case is faster than a fixed sleep) and gives up after
# `timeout` (so a loaded machine does not make the spec fail), returning the last answer.
def eventually(timeout : Time::Span = 3.seconds, & : -> Bool) : Bool
  deadline = Time.instant + timeout
  until (result = yield) || Time.instant >= deadline
    sleep 10.milliseconds
  end
  result
end
