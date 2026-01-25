require "./spec_helper"

describe Session::RetryConfig do
  describe "#initialize" do
    it "has sensible defaults" do
      config = Session::RetryConfig.new

      config.max_attempts.should eq 3
      config.base_delay.should eq 100.milliseconds
      config.max_delay.should eq 5.seconds
      config.backoff_multiplier.should eq 2.0
      config.jitter.should eq 0.1
    end

    it "accepts custom values" do
      config = Session::RetryConfig.new(
        max_attempts: 5,
        base_delay: 50.milliseconds,
        max_delay: 10.seconds,
        backoff_multiplier: 3.0,
        jitter: 0.2
      )

      config.max_attempts.should eq 5
      config.base_delay.should eq 50.milliseconds
      config.max_delay.should eq 10.seconds
      config.backoff_multiplier.should eq 3.0
      config.jitter.should eq 0.2
    end
  end
end

describe Session::Retry do
  describe ".with_retry" do
    it "returns result on success" do
      config = Session::RetryConfig.new(max_attempts: 3)

      result = Session::Retry.with_retry(config) do
        42
      end

      result.should eq 42
    end

    it "retries on failure" do
      config = Session::RetryConfig.new(
        max_attempts: 3,
        base_delay: 1.millisecond
      )
      attempts = 0

      result = Session::Retry.with_retry(config) do
        attempts += 1
        raise "error" if attempts < 2
        "success"
      end

      result.should eq "success"
      attempts.should eq 2
    end

    it "raises after max attempts" do
      config = Session::RetryConfig.new(
        max_attempts: 2,
        base_delay: 1.millisecond
      )
      attempts = 0

      expect_raises(Exception, "always fails") do
        Session::Retry.with_retry(config) do
          attempts += 1
          raise "always fails"
        end
      end

      attempts.should eq 2
    end
  end

  describe ".with_retry_if" do
    it "retries only matching exceptions" do
      config = Session::RetryConfig.new(
        max_attempts: 3,
        base_delay: 1.millisecond
      )
      attempts = 0

      result = Session::Retry.with_retry_if(
        ->(ex : Exception) { ex.message == "retry me" },
        config
      ) do
        attempts += 1
        raise "retry me" if attempts < 2
        "done"
      end

      result.should eq "done"
      attempts.should eq 2
    end

    it "does not retry non-matching exceptions" do
      config = Session::RetryConfig.new(
        max_attempts: 3,
        base_delay: 1.millisecond
      )
      attempts = 0

      expect_raises(Exception, "don't retry") do
        Session::Retry.with_retry_if(
          ->(ex : Exception) { ex.message == "retry me" },
          config
        ) do
          attempts += 1
          raise "don't retry"
        end
      end

      attempts.should eq 1 # Should not have retried
    end
  end

  describe ".retryable_connection_error?" do
    it "returns true for IO::Error" do
      ex = IO::Error.new("connection failed")
      Session::Retry.retryable_connection_error?(ex).should be_true
    end

    it "returns false for generic exceptions" do
      ex = Exception.new("generic error")
      Session::Retry.retryable_connection_error?(ex).should be_false
    end
  end

  describe ".retryable_timeout_error?" do
    it "returns true for IO::TimeoutError" do
      ex = IO::TimeoutError.new("timeout")
      Session::Retry.retryable_timeout_error?(ex).should be_true
    end

    it "returns false for generic exceptions" do
      ex = Exception.new("generic error")
      Session::Retry.retryable_timeout_error?(ex).should be_false
    end
  end
end
