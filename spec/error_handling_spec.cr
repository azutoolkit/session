require "./spec_helper"

describe "Error Handling & Resilience" do
  describe "Exception Types" do
    it "raises SessionExpiredException for expired sessions" do
      expect_raises(Session::SessionExpiredException, "Session has expired") do
        raise Session::SessionExpiredException.new
      end
    end

    it "raises SessionCorruptionException for corrupted data" do
      expect_raises(Session::SessionCorruptionException, "Session data is corrupted") do
        raise Session::SessionCorruptionException.new
      end
    end

    it "raises StorageConnectionException for connection failures" do
      expect_raises(Session::StorageConnectionException, "Storage connection failed") do
        raise Session::StorageConnectionException.new
      end
    end

    it "raises SessionNotFoundException for missing sessions" do
      expect_raises(Session::SessionNotFoundException, "Session not found") do
        raise Session::SessionNotFoundException.new
      end
    end

    it "raises SessionValidationException for validation failures" do
      expect_raises(Session::SessionValidationException, "Session validation failed") do
        raise Session::SessionValidationException.new
      end
    end

    it "raises SessionSerializationException for serialization failures" do
      expect_raises(Session::SessionSerializationException, "Session serialization failed") do
        raise Session::SessionSerializationException.new
      end
    end

    it "raises SessionEncryptionException for encryption failures" do
      expect_raises(Session::SessionEncryptionException, "Session encryption/decryption failed") do
        raise Session::SessionEncryptionException.new
      end
    end

    it "preserves cause exception in custom exceptions" do
      original_error = Exception.new("Original error")
      session_error = Session::SessionCorruptionException.new("Corrupted", original_error)

      session_error.cause.should eq(original_error)
    end
  end

  describe "Retry Configuration" do
    it "creates RetryConfig with default values" do
      config = Session::RetryConfig.new

      config.max_attempts.should eq(3)
      config.base_delay.should eq(100.milliseconds)
      config.max_delay.should eq(5.seconds)
      config.backoff_multiplier.should eq(2.0)
      config.jitter.should eq(0.1)
    end

    it "creates RetryConfig with custom values" do
      config = Session::RetryConfig.new(
        max_attempts: 5,
        base_delay: 200.milliseconds,
        max_delay: 10.seconds,
        backoff_multiplier: 1.5,
        jitter: 0.2
      )

      config.max_attempts.should eq(5)
      config.base_delay.should eq(200.milliseconds)
      config.max_delay.should eq(10.seconds)
      config.backoff_multiplier.should eq(1.5)
      config.jitter.should eq(0.2)
    end
  end

  describe "Retry Logic" do
    it "succeeds on first attempt" do
      attempts = 0
      result = Session::Retry.with_retry do
        attempts += 1
        "success"
      end

      result.should eq("success")
      attempts.should eq(1)
    end

    it "retries on failure and succeeds" do
      attempts = 0
      result = Session::Retry.with_retry do
        attempts += 1
        if attempts < 3
          raise "Temporary failure"
        else
          "success"
        end
      end

      result.should eq("success")
      attempts.should eq(3)
    end

    it "fails after max attempts" do
      attempts = 0
      expect_raises(Exception, "Permanent failure") do
        Session::Retry.with_retry do
          attempts += 1
          raise "Permanent failure"
        end
      end

      attempts.should eq(3) # Default max_attempts
    end

    it "retries only on specific exceptions" do
      attempts = 0
      expect_raises(Exception, "Non-retryable error") do
        Session::Retry.with_retry_if(
          ->(ex : Exception) { ex.message == "Retryable error" }
        ) do
          attempts += 1
          raise "Non-retryable error"
        end
      end

      attempts.should eq(1) # Should not retry
    end

    it "retries on retryable exceptions" do
      attempts = 0
      result = Session::Retry.with_retry_if(
        ->(ex : Exception) { ex.message == "Retryable error" }
      ) do
        attempts += 1
        if attempts < 3
          raise "Retryable error"
        else
          "success"
        end
      end

      result.should eq("success")
      attempts.should eq(3)
    end

    it "calculates delay with exponential backoff" do
      config = Session::RetryConfig.new(
        base_delay: 100.milliseconds,
        backoff_multiplier: 2.0,
        jitter: 0.0 # No jitter for predictable testing
      )

      start_time = Time.monotonic
      attempts = 0

      Session::Retry.with_retry(config) do
        attempts += 1
        if attempts < 3
          raise "Retryable error"
        else
          "success"
        end
      end

      elapsed = Time.monotonic - start_time
      # Should have delays of ~100ms and ~200ms
      elapsed.should be >= 300.milliseconds
    end
  end

  describe "Retry Predicates" do
    it "identifies retryable connection errors" do
      # Note: These tests would need actual Redis connection errors
      # For now, we test the predicate logic
      io_error = IO::Error.new("Connection refused")
      Session::Retry.retryable_connection_error?(io_error).should be_true
    end

    it "identifies retryable timeout errors" do
      timeout_error = IO::TimeoutError.new("Operation timed out")
      Session::Retry.retryable_timeout_error?(timeout_error).should be_true
    end

    it "identifies retryable network errors" do
      io_error = IO::Error.new("Network unreachable")
      Session::Retry.retryable_network_error?(io_error).should be_true
    end
  end

  describe "Configuration Error Handling" do
    it "has default retry configuration" do
      Session.config.retry_config.should be_a(Session::RetryConfig)
      Session.config.enable_retry.should be_true
      Session.config.log_errors.should be_true
      Session.config.fail_fast_on_corruption.should be_true
    end

    it "allows custom retry configuration" do
      original_config = Session.config.retry_config

      Session.configure do |c|
        c.retry_config = Session::RetryConfig.new(max_attempts: 5)
        c.enable_retry = false
        c.log_errors = false
        c.fail_fast_on_corruption = false
      end

      Session.config.retry_config.max_attempts.should eq(5)
      Session.config.enable_retry.should be_false
      Session.config.log_errors.should be_false
      Session.config.fail_fast_on_corruption.should be_false

      # Restore original config
      Session.configure do |c|
        c.retry_config = original_config
        c.enable_retry = true
        c.log_errors = true
        c.fail_fast_on_corruption = true
      end
    end
  end
end
