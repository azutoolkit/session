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

# Reset configuration to defaults before each test
def reset_config
  Session.config.store = Session::MemoryStore(UserSession).new
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
