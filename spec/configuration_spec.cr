require "./spec_helper"
require "log/spec"

describe Session::Configuration do
  describe "#using_default_secret?" do
    it "returns true when using default secret" do
      Session.config.using_default_secret?.should be_true
    end

    it "returns false when custom secret is set" do
      Session.config.secret = "my-custom-secret-key-32-bytes!!!"
      Session.config.using_default_secret?.should be_false
    end
  end

  describe "#validate_secret!" do
    it "does nothing when custom secret is set" do
      Session.config.secret = "my-custom-secret-key-32-bytes!!!"
      Session.config.validate_secret!
      # Should not raise
    end

    it "raises when require_secure_secret is true and using default" do
      Session.config.require_secure_secret = true
      expect_raises(Session::InsecureSecretException) do
        Session.config.validate_secret!
      end
    end

    it "does not raise when require_secure_secret is true and custom secret set" do
      Session.config.secret = "my-custom-secret-key-32-bytes!!!"
      Session.config.require_secure_secret = true
      Session.config.validate_secret!
      # Should not raise
    end
  end

  describe "digest configuration" do
    it "defaults to sha256" do
      Session.config.digest_algorithm.should eq :sha256
    end

    it "defaults to fallback enabled" do
      Session.config.digest_fallback.should be_true
    end
  end

  describe "KDF configuration" do
    it "defaults to disabled" do
      Session.config.use_kdf.should be_false
    end

    it "has default iterations of 100_000" do
      Session.config.kdf_iterations.should eq 100_000
    end
  end

  describe "compression configuration" do
    it "defaults to disabled" do
      Session.config.compress_data.should be_false
    end

    it "has default threshold of 256 bytes" do
      Session.config.compression_threshold.should eq 256
    end
  end

  describe "sliding expiration configuration" do
    it "defaults to disabled" do
      Session.config.sliding_expiration.should be_false
    end
  end

  describe "session binding configuration" do
    it "defaults to no binding" do
      Session.config.bind_to_ip.should be_false
      Session.config.bind_to_user_agent.should be_false
    end
  end

  describe "circuit breaker configuration" do
    it "defaults to disabled" do
      Session.config.circuit_breaker_enabled.should be_false
    end

    it "has reasonable default config" do
      config = Session.config.circuit_breaker_config
      config.failure_threshold.should eq 5
      config.reset_timeout.should eq 30.seconds
      config.half_open_max_calls.should eq 1
    end
  end

  describe "#session" do
    it "returns configured store" do
      store = Session::MemoryStore(UserSession).new
      Session.config.store = store

      Session.config.session.should eq store
    end

    it "raises when store is not configured" do
      Session.config.store = nil

      expect_raises(Exception, "Session store not configured") do
        Session.config.session
      end
    end
  end

  describe "#encryptor" do
    it "returns a Message::Encryptor" do
      Session.config.encryptor.should be_a Message::Encryptor
    end

    it "raises InsecureSecretException when require_secure_secret and using default" do
      Session.config.require_secure_secret = true

      expect_raises(Session::InsecureSecretException) do
        Session.config.encryptor
      end
    end

    it "passes KDF settings to encryptor" do
      Session.config.secret = "my-custom-secret-key-32-bytes!!!"
      Session.config.use_kdf = true
      Session.config.kdf_iterations = 50_000

      encryptor = Session.config.encryptor
      encryptor.should be_a Message::Encryptor
    end
  end

  describe "lifecycle callbacks" do
    it "fires on_started when session is created" do
      fired = false
      received_sid = ""
      Session.config.on_started = ->(sid : String, _data : Session::Base) {
        fired = true
        received_sid = sid
        nil
      }

      store = Session::MemoryStore(UserSession).new
      store.create

      fired.should be_true
      received_sid.should eq store.session_id
    end

    it "fires on_deleted when session is deleted" do
      fired = false
      Session.config.on_deleted = ->(_sid : String, _data : Session::Base) {
        fired = true
        nil
      }

      store = Session::MemoryStore(UserSession).new
      store.create
      cookies = HTTP::Cookies.new
      store.set_cookies(cookies)

      store.delete

      fired.should be_true
    end

    it "fires on_loaded when session is loaded" do
      fired = false
      Session.config.on_loaded = ->(_sid : String, _data : Session::Base) {
        fired = true
        nil
      }

      store = Session::MemoryStore(UserSession).new
      store.create
      cookies = HTTP::Cookies.new
      cookies << store.create_session_cookie("localhost")
      store.set_cookies(cookies)

      store.load_from(cookies)

      fired.should be_true
    end

    it "fires on_client when cookies are set" do
      fired = false
      Session.config.on_client = ->(_sid : String, _data : Session::Base) {
        fired = true
        nil
      }

      store = Session::MemoryStore(UserSession).new
      store.create
      cookies = HTTP::Cookies.new
      store.set_cookies(cookies)

      fired.should be_true
    end

    it "fires on_regenerated when session ID is regenerated" do
      old_id = ""
      new_id = ""
      Session.config.on_regenerated = ->(old_sid : String, new_sid : String, _data : Session::Base) {
        old_id = old_sid
        new_id = new_sid
        nil
      }

      store = Session::MemoryStore(UserSession).new
      store.create
      original_id = store.session_id
      cookies = HTTP::Cookies.new
      store.set_cookies(cookies)

      store.regenerate_id

      old_id.should eq original_id
      new_id.should eq store.session_id
      old_id.should_not eq new_id
    end
  end

  describe "error handling configuration" do
    it "defaults fail_fast_on_corruption to true" do
      Session.config.fail_fast_on_corruption.should be_true
    end

    it "defaults enable_retry to true" do
      Session.config.enable_retry.should be_true
    end

    it "defaults log_errors to true" do
      Session.config.log_errors.should be_true
    end
  end
end

describe Session::Configuration do
  describe "the default secret outside development" do
    around_each do |example|
      previous = ENV["CRYSTAL_ENV"]?
      example.run
      previous ? (ENV["CRYSTAL_ENV"] = previous) : ENV.delete("CRYSTAL_ENV")
    end

    {"production", "staging"}.each do |environment|
      it "is refused in #{environment}" do
        ENV["CRYSTAL_ENV"] = environment
        config = Session::Configuration.new

        config.require_secure_secret.should be_true
        expect_raises(Session::InsecureSecretException) { config.validate_secret! }
      end
    end

    it "is only warned about in development" do
      ENV["CRYSTAL_ENV"] = "development"
      config = Session::Configuration.new

      config.require_secure_secret.should be_false
      config.validate_secret!
    end

    it "can still be switched off explicitly" do
      ENV["CRYSTAL_ENV"] = "production"
      config = Session::Configuration.new
      config.require_secure_secret = false

      config.validate_secret!
    end

    it "does not get in the way of a real secret in production" do
      ENV["CRYSTAL_ENV"] = "production"
      config = Session::Configuration.new
      config.secret = "a-secret-nobody-else-knows-0123456789"

      config.validate_secret!
    end
  end
end

describe Session::Configuration do
  describe "without a configured secret" do
    around_each do |example|
      previous = {ENV["CRYSTAL_ENV"]?, ENV["SESSION_SECRET"]?}
      ENV.delete("SESSION_SECRET")
      ENV["CRYSTAL_ENV"] = "development"
      example.run
    ensure
      {"CRYSTAL_ENV", "SESSION_SECRET"}.zip(previous.not_nil!).each do |name, value|
        value ? (ENV[name] = value) : ENV.delete(name)
      end
    end

    it "never signs with the published default secret" do
      config = Session::Configuration.new

      config.secret.should_not eq Session::Configuration::DEFAULT_SECRET
      config.using_default_secret?.should be_false
      config.secret.should eq Session::Configuration.new.secret
    end

    it "reads SESSION_SECRET" do
      ENV["SESSION_SECRET"] = "from-the-environment-0123456789abcdef"

      Session::Configuration.new.secret.should eq "from-the-environment-0123456789abcdef"
    end

    it "is refused in production even when CRYSTAL_ENV is set after the configuration was built" do
      config = Session::Configuration.new
      ENV["CRYSTAL_ENV"] = "Production"

      expect_raises(Session::InsecureSecretException, /SESSION_SECRET/) { config.encryptor }
    end

    it "is refused in production even after the random fallback was used" do
      config = Session::Configuration.new
      config.encryptor
      ENV["CRYSTAL_ENV"] = "production"

      expect_raises(Session::InsecureSecretException, /SESSION_SECRET/) { config.encryptor }
    end

    it "refuses a SESSION_SECRET shorter than 32 bytes with a clear message" do
      ENV["SESSION_SECRET"] = "short"

      expect_raises(Session::InsecureSecretException, /at least 32 bytes/) { Session::Configuration.new.encryptor }
    end

    it "refuses an empty configured secret with a clear message" do
      config = Session::Configuration.new
      config.secret = ""

      expect_raises(Session::InsecureSecretException, /at least 32 bytes/) { config.encryptor }
    end
  end
end

describe Session::SessionHandler do
  it "fails the request when the cookie store has no usable secret, instead of answering without a session" do
    Session.config.secret = "short"
    handler = Session::SessionHandler.new(Session::CookieStore(UserSession).new)
    context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/"), HTTP::Server::Response.new(IO::Memory.new))

    expect_raises(Session::InsecureSecretException) { handler.call(context) }
  end
end

describe Session::Configuration do
  describe "a short secret with key derivation on" do
    # The HMAC signature uses the raw secret, so PBKDF2 does not make a short one safe.
    ["", "a", "abc", "31-bytes-is-still-too-short-xyz"].each do |short|
      it "refuses #{short.bytesize} bytes under the production preset" do
        config = Session::Configuration.new
        config.apply_preset(:production)
        config.secret = short

        config.use_kdf.should be_true
        expect_raises(Session::InsecureSecretException, /at least 32 bytes/) { config.encryptor }
      end
    end
  end

  describe "#encryptor" do
    it "reuses the encryptor (and its derived key) while the settings stay the same" do
      config = Session::Configuration.new
      config.secret = "a-secret-nobody-else-knows-0123456789"
      config.use_kdf = true
      config.kdf_iterations = 1_000

      config.encryptor.should be config.encryptor
    end

    it "builds a new encryptor when a setting it depends on changes" do
      config = Session::Configuration.new
      config.secret = "a-secret-nobody-else-knows-0123456789"
      config.use_kdf = true
      config.kdf_iterations = 1_000
      first = config.encryptor

      config.kdf_salt = "another-salt"
      config.encryptor.should_not be first
      second = config.encryptor

      config.secret = "another-secret-nobody-knows-0123456789"
      config.encryptor.should_not be second
    end

    it "reads the secret once per call" do
      config = SecretReadCounter.new
      config.secret = "a-secret-nobody-else-knows-0123456789"

      config.encryptor
      config.reads.should eq 1
      config.encryptor
      config.reads.should eq 2
    end

    it "gives every fiber a working encryptor while the settings change" do
      config = Session::Configuration.new
      config.secret = "a-secret-nobody-else-knows-0123456789"
      done = Channel(Exception?).new

      8.times do |i|
        spawn do
          50.times { |j| config.kdf_salt = "salt-#{(i + j) % 3}"; config.encryptor.encrypt_and_sign("data") }
          done.send(nil)
        rescue ex
          done.send(ex)
        end
      end

      8.times { done.receive.should be_nil }
    end
  end

  describe "the default secret messages" do
    it "suggest a secret that is long enough" do
      config = Session::Configuration.new
      config.secret = Session::Configuration::DEFAULT_SECRET
      config.require_secure_secret = true

      error = expect_raises(Session::InsecureSecretException) { config.validate_secret! }
      error.message.to_s.should contain "openssl rand -hex 32"
      error.message.to_s.should_not contain "your-"
    end

    it "warn with a secret that is long enough" do
      config = Session::Configuration.new
      config.secret = Session::Configuration::DEFAULT_SECRET
      config.require_secure_secret = false

      Log.capture do |logs|
        config.validate_secret!
        logs.check(:warn, /openssl rand -hex 32/)
        logs.entry.message.should_not contain "your-"
      end
    end
  end

  describe "#validate_secret_for!" do
    it "refuses a short secret for a store that encrypts with it" do
      Session.config.secret = "short"

      expect_raises(Session::InsecureSecretException, /at least 32 bytes/) do
        Session.config.validate_secret_for!(Session::CookieStore(UserSession).new)
      end
    end

    it "does not check the secret for a store that does not use it" do
      Session.config.secret = "short"

      Session.config.validate_secret_for!(Session::MemoryStore(UserSession).new)
    end
  end
end

# Counts the reads of `secret`: each one reads the environment when no secret is configured.
class SecretReadCounter < Session::Configuration
  getter reads = 0

  def secret : String
    @reads += 1
    super
  end
end

describe "reset_config" do
  it "restores what a preset and the cookie options change" do
    config = Session.config
    config.apply_preset(:high_security)
    config.kdf_salt = "another-salt"
    config.cookie_secure = false
    config.cookie_same_site = HTTP::Cookie::SameSite::Lax
    config.allow_insecure_cookies = true
    config.retry_config = Session::RetryConfig.new(max_attempts: 9)
    config.circuit_breaker_config = Session::CircuitBreakerConfig.new(failure_threshold: 99)

    reset_config

    defaults = Session::Configuration.new
    {% for name in %w(timeout encrypt_redis_data sliding_expiration log_errors circuit_breaker_enabled enable_retry
                     compress_data compression_threshold bind_to_ip bind_to_user_agent use_kdf kdf_iterations kdf_salt
                     digest_algorithm digest_fallback fail_fast_on_corruption cookie_secure cookie_same_site
                     allow_insecure_cookies) %}
      config.{{name.id}}.should eq defaults.{{name.id}}
    {% end %}
    config.retry_config.max_attempts.should eq defaults.retry_config.max_attempts
    config.circuit_breaker_config.failure_threshold.should eq defaults.circuit_breaker_config.failure_threshold
    config.cluster.enabled.should be_false
  end
end

# Encrypts with the secret when `encrypt_redis_data` is on, as `RedisStore` does, without a Redis server.
class RedisLikeStore < Session::MemoryStore(UserSession)
  def encrypts_with_secret? : Bool
    Session.config.encrypt_redis_data
  end
end

describe "Session.configure" do
  it "fails at boot when the configured store encrypts with an unusable secret" do
    expect_raises(Session::InsecureSecretException, /at least 32 bytes/) do
      Session.configure do |c|
        c.store = RedisLikeStore.new
        c.encrypt_redis_data = true
        c.secret = "short"
      end
    end
  end

  it "fails at boot under the production preset with a short secret" do
    expect_raises(Session::InsecureSecretException, /at least 32 bytes/) do
      Session.configure do |c|
        c.apply_preset(:production)
        c.store = RedisLikeStore.new
        c.secret = "abc"
      end
    end
  end

  it "checks the secret without a store when encrypt_redis_data is on" do
    expect_raises(Session::InsecureSecretException, /at least 32 bytes/) do
      Session.configure do |c|
        c.store = nil
        c.encrypt_redis_data = true
        c.secret = "short"
      end
    end
  end

  it "does not check the secret without a store when encrypt_redis_data is off" do
    Session.configure do |c|
      c.store = nil
      c.secret = "short"
    end
  end

  it "does not check the secret when the store does not encrypt" do
    Session.configure do |c|
      c.secret = "short"
    end
  end

  describe "a memory store in production without a secret" do
    around_each do |example|
      previous = {ENV["CRYSTAL_ENV"]?, ENV["SESSION_SECRET"]?}
      ENV.delete("SESSION_SECRET")
      ENV["CRYSTAL_ENV"] = "production"
      example.run
    ensure
      {"CRYSTAL_ENV", "SESSION_SECRET"}.zip(previous.not_nil!).each do |name, value|
        value ? (ENV[name] = value) : ENV.delete(name)
      end
    end

    {:production, :high_security, :clustered}.each do |preset|
      it "boots under the #{preset} preset: the memory store never reads the secret" do
        Session.configure do |c|
          c.apply_preset(preset)
          c.store = Session::MemoryStore(UserSession).new
          c.secret = nil
        end

        Session.config.encrypt_redis_data.should be_true
      end
    end

    it "serves requests under the production preset" do
      store = Session::MemoryStore(UserSession).new
      Session.configure do |c|
        c.apply_preset(:production)
        c.store = store
        c.secret = nil
      end
      handler = Session::SessionHandler.new(store)
      handler.next = ->(context : HTTP::Server::Context) { context.response.status_code = 200 }
      context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/"), HTTP::Server::Response.new(IO::Memory.new))

      handler.call(context)

      context.response.status_code.should eq 200
    end
  end
end

describe "Store#encrypts_with_secret?" do
  it "is false for a memory store, whatever encrypt_redis_data says" do
    Session.config.encrypt_redis_data = true

    Session::MemoryStore(UserSession).new.encrypts_with_secret?.should be_false
  end

  it "is true for a cookie store" do
    Session::CookieStore(UserSession).new.encrypts_with_secret?.should be_true
  end

  if REDIS_AVAILABLE
    it "follows encrypt_redis_data for a Redis store" do
      store = Session::RedisStore(UserSession).new(client: redis_client)

      Session.config.encrypt_redis_data = true
      store.encrypts_with_secret?.should be_true
      Session.config.encrypt_redis_data = false
      store.encrypts_with_secret?.should be_false
    end
  end
end
