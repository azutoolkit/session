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
end
