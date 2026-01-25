require "./spec_helper"

describe Session::CircuitBreaker do
  describe "#initialize" do
    it "starts in closed state" do
      cb = Session::CircuitBreaker.new
      cb.state.should eq Session::CircuitState::Closed
      cb.failure_count.should eq 0
    end

    it "uses provided config" do
      config = Session::CircuitBreakerConfig.new(
        failure_threshold: 3,
        reset_timeout: 10.seconds
      )
      cb = Session::CircuitBreaker.new(config)

      cb.config.failure_threshold.should eq 3
      cb.config.reset_timeout.should eq 10.seconds
    end
  end

  describe "#call" do
    it "executes block when closed" do
      cb = Session::CircuitBreaker.new
      result = cb.call { 42 }
      result.should eq 42
    end

    it "returns result from block" do
      cb = Session::CircuitBreaker.new
      result = cb.call { "hello" }
      result.should eq "hello"
    end

    it "propagates exceptions" do
      cb = Session::CircuitBreaker.new
      expect_raises(Exception, "test error") do
        cb.call { raise "test error" }
      end
    end

    it "tracks failures" do
      cb = Session::CircuitBreaker.new

      begin
        cb.call { raise "error" }
      rescue
      end

      cb.failure_count.should eq 1
    end

    it "opens circuit after threshold failures" do
      config = Session::CircuitBreakerConfig.new(failure_threshold: 2)
      cb = Session::CircuitBreaker.new(config)

      2.times do
        begin
          cb.call { raise "error" }
        rescue
        end
      end

      cb.state.should eq Session::CircuitState::Open
    end

    it "raises CircuitOpenException when open" do
      config = Session::CircuitBreakerConfig.new(failure_threshold: 1)
      cb = Session::CircuitBreaker.new(config)

      begin
        cb.call { raise "error" }
      rescue
      end

      expect_raises(Session::CircuitOpenException) do
        cb.call { "should not execute" }
      end
    end

    it "resets failure count on success" do
      cb = Session::CircuitBreaker.new

      begin
        cb.call { raise "error" }
      rescue
      end

      cb.failure_count.should eq 1

      cb.call { "success" }

      cb.failure_count.should eq 0
    end
  end

  describe "#allow_request?" do
    it "returns true when closed" do
      cb = Session::CircuitBreaker.new
      cb.allow_request?.should be_true
    end

    it "returns false when open and timeout not elapsed" do
      config = Session::CircuitBreakerConfig.new(
        failure_threshold: 1,
        reset_timeout: 1.hour
      )
      cb = Session::CircuitBreaker.new(config)

      begin
        cb.call { raise "error" }
      rescue
      end

      cb.allow_request?.should be_false
    end
  end

  describe "#reset!" do
    it "closes circuit and resets counters" do
      config = Session::CircuitBreakerConfig.new(failure_threshold: 1)
      cb = Session::CircuitBreaker.new(config)

      begin
        cb.call { raise "error" }
      rescue
      end

      cb.state.should eq Session::CircuitState::Open

      cb.reset!

      cb.state.should eq Session::CircuitState::Closed
      cb.failure_count.should eq 0
    end
  end

  describe "#time_until_retry" do
    it "returns nil when closed" do
      cb = Session::CircuitBreaker.new
      cb.time_until_retry.should be_nil
    end

    it "returns remaining time when open" do
      config = Session::CircuitBreakerConfig.new(
        failure_threshold: 1,
        reset_timeout: 30.seconds
      )
      cb = Session::CircuitBreaker.new(config)

      begin
        cb.call { raise "error" }
      rescue
      end

      time = cb.time_until_retry
      time.should_not be_nil
      time.not_nil!.total_seconds.should be > 0
      time.not_nil!.total_seconds.should be <= 30
    end
  end
end

describe Session::CircuitBreakerConfig do
  describe "#initialize" do
    it "has sensible defaults" do
      config = Session::CircuitBreakerConfig.new

      config.failure_threshold.should eq 5
      config.reset_timeout.should eq 30.seconds
      config.half_open_max_calls.should eq 1
    end

    it "accepts custom values" do
      config = Session::CircuitBreakerConfig.new(
        failure_threshold: 10,
        reset_timeout: 1.minute,
        half_open_max_calls: 3
      )

      config.failure_threshold.should eq 10
      config.reset_timeout.should eq 1.minute
      config.half_open_max_calls.should eq 3
    end
  end
end

describe Session::CircuitOpenException do
  it "includes time until retry in message" do
    ex = Session::CircuitOpenException.new(30.seconds)
    ex.message.not_nil!.should contain("30")
    ex.time_until_retry.should eq 30.seconds
  end
end
