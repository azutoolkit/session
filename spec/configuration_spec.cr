require "./spec_helper"

describe Session::Configuration do
  describe "#using_default_secret?" do
    it "returns true when using default secret" do
      Session.config.using_default_secret?.should be_true
    end

    it "returns false when custom secret is set" do
      Session.config.secret = "my-custom-secret-key-32-bytes!!"
      Session.config.using_default_secret?.should be_false
    end
  end

  describe "#validate_secret!" do
    it "does nothing when custom secret is set" do
      Session.config.secret = "my-custom-secret-key-32-bytes!!"
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
      Session.config.secret = "my-custom-secret-key-32-bytes!!"
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
      Session.config.secret = "my-custom-secret-key-32-bytes!!"
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
