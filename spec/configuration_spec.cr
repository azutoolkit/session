require "./spec_helper"

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
