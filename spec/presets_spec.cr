require "./spec_helper"

describe Session::Presets do
  describe ".development" do
    it "sets development-appropriate defaults" do
      config = Session::Presets.development

      config.timeout.should eq 30.minutes
      config.require_secure_secret.should be_false
      config.encrypt_redis_data.should be_false
      config.sliding_expiration.should be_true
      config.circuit_breaker_enabled.should be_false
      config.enable_retry.should be_false
      config.compress_data.should be_false
      config.bind_to_ip.should be_false
      config.bind_to_user_agent.should be_false
    end
  end

  describe ".production" do
    it "sets production-appropriate defaults" do
      config = Session::Presets.production

      config.timeout.should eq 1.hour
      config.require_secure_secret.should be_true
      config.encrypt_redis_data.should be_true
      config.sliding_expiration.should be_true
      config.circuit_breaker_enabled.should be_true
      config.enable_retry.should be_true
      config.compress_data.should be_true
      config.compression_threshold.should eq 256
      config.use_kdf.should be_true
      config.digest_algorithm.should eq :sha256
    end
  end

  describe ".high_security" do
    it "sets high security defaults" do
      config = Session::Presets.high_security

      config.timeout.should eq 15.minutes
      config.require_secure_secret.should be_true
      config.encrypt_redis_data.should be_true
      config.bind_to_ip.should be_true
      config.bind_to_user_agent.should be_true
      config.use_kdf.should be_true
      config.kdf_iterations.should eq 100_000
      config.digest_fallback.should be_false
      config.fail_fast_on_corruption.should be_true
    end
  end

  describe ".testing" do
    it "sets testing-appropriate defaults" do
      config = Session::Presets.testing

      config.timeout.should eq 5.minutes
      config.require_secure_secret.should be_false
      config.encrypt_redis_data.should be_false
      config.sliding_expiration.should be_false
      config.log_errors.should be_false
      config.circuit_breaker_enabled.should be_false
      config.enable_retry.should be_false
      config.compress_data.should be_false
      config.bind_to_ip.should be_false
      config.bind_to_user_agent.should be_false
    end
  end

  describe ".clustered" do
    it "extends production with clustering" do
      config = Session::Presets.clustered

      # Should have production settings
      config.timeout.should eq 1.hour
      config.require_secure_secret.should be_true
      config.encrypt_redis_data.should be_true

      # Plus clustering
      config.cluster.enabled.should be_true
      config.cluster.local_cache_enabled.should be_true
      config.cluster.local_cache_ttl.should eq 30.seconds
      config.cluster.local_cache_max_size.should eq 10_000
    end
  end
end

describe Session::Configuration do
  describe ".from_preset" do
    it "loads a preset as a new Configuration" do
      config = Session::Configuration.from_preset(:testing)

      config.should be_a Session::Configuration
      config.timeout.should eq 5.minutes
    end

    it "raises for unknown preset" do
      expect_raises(ArgumentError, "Unknown preset: invalid") do
        Session::Configuration.from_preset(:invalid)
      end
    end
  end

  describe "#apply_preset" do
    it "applies preset settings to existing configuration" do
      Session.config.timeout.should eq 1.hour
      Session.config.apply_preset(:development)

      Session.config.timeout.should eq 30.minutes
      Session.config.sliding_expiration.should be_true
      Session.config.enable_retry.should be_false
    end

    it "preserves secret when applying preset" do
      Session.config.secret = "my-custom-secret-key-32-bytes!!"
      Session.config.apply_preset(:production)

      Session.config.secret.should eq "my-custom-secret-key-32-bytes!!"
    end

    it "raises for unknown preset" do
      expect_raises(ArgumentError, "Unknown preset: bogus") do
        Session.config.apply_preset(:bogus)
      end
    end
  end
end
