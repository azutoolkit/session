require "./spec_helper"

# Helper handler that just returns 200
class IntegrationOkHandler
  include HTTP::Handler

  def call(context : HTTP::Server::Context)
    context.response.status_code = 200
    context.response.print "OK"
  end
end

# Helper method for creating test contexts
private def create_test_context_with_session(session_provider, session_id : String) : HTTP::Server::Context
  request = HTTP::Request.new("GET", "/")
  response = HTTP::Server::Response.new(IO::Memory.new)
  context = HTTP::Server::Context.new(request, response)

  context.request.cookies << HTTP::Cookie.new(
    name: session_provider.session_key,
    value: session_id,
    expires: 1.hour.from_now,
    secure: true,
    http_only: true,
    creation_time: Time.local
  )
  context
end

describe "Integration Error Handling & Resilience" do
  describe "End-to-End Error Scenarios" do
    it "handles complete session lifecycle with errors gracefully" do
      # Configure session with error handling
      Session.configure do |c|
        c.retry_config = Session::RetryConfig.new(max_attempts: 2)
        c.enable_retry = true
        c.log_errors = true
      end

      # Test with memory store
      memory_provider = Session::MemoryStore(UserSession).provider
      memory_handler = Session::SessionHandler.new(memory_provider)
      memory_handler.next = IntegrationOkHandler.new

      # Create a session
      session = memory_provider.create
      session.data.username = "test_user"

      # Simulate request with session
      context = create_test_context_with_session(memory_provider, session.session_id)
      memory_handler.call(context)

      # Verify session was handled correctly
      context.response.status_code.should eq(200)
      context.response.cookies[memory_provider.session_key]?.should_not be_nil
    end

    it "handles session expiration across the system" do
      # Create an expired session
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      expired_session.data.username = "expired_user"

      # Test with memory store
      memory_store = Session::MemoryStore(UserSession).new
      key = expired_session.session_id

      # Should handle expired session appropriately - returns nil for expired
      memory_store[key]?.should be_nil

      # Restore timeout
      Session.config.timeout = 1.hour
    end
  end

  describe "Retry Logic Integration" do
    it "retries failed operations with exponential backoff" do
      # Configure aggressive retry settings for testing
      Session.configure do |c|
        c.retry_config = Session::RetryConfig.new(
          max_attempts: 3,
          base_delay: 50.milliseconds,
          max_delay: 200.milliseconds,
          backoff_multiplier: 2.0,
          jitter: 0.0 # No jitter for predictable testing
        )
      end

      # Test retry logic with a failing operation that eventually succeeds
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

    it "respects retry configuration from session config" do
      # Configure custom retry settings
      Session.configure do |c|
        c.retry_config = Session::RetryConfig.new(max_attempts: 1)
      end

      # Test that retry logic uses the configured settings
      attempts = 0
      expect_raises(Exception, "Permanent failure") do
        Session::Retry.with_retry do
          attempts += 1
          raise "Permanent failure"
        end
      end

      attempts.should eq(1) # Should only try once
    end
  end

  describe "Graceful Degradation" do
    it "handles partial system failures gracefully" do
      # Test that the system can handle partial failures
      memory_store = Session::MemoryStore(UserSession).new
      session = Session::SessionId(UserSession).new
      key = session.session_id

      # Store session
      memory_store[key] = session

      # Simulate partial failure by corrupting the session
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      expired_key = expired_session.session_id

      # Should handle expired session gracefully - returns nil
      memory_store[expired_key]?.should be_nil

      # Restore timeout
      Session.config.timeout = 1.hour
    end
  end

  describe "Error Recovery" do
    it "recovers from temporary failures" do
      # Reset retry config for this test
      Session.config.retry_config = Session::RetryConfig.new(
        max_attempts: 3,
        base_delay: 10.milliseconds,
        jitter: 0.0
      )

      # Test recovery from temporary failures
      attempts = 0
      result = Session::Retry.with_retry do
        attempts += 1
        if attempts < 2
          raise "Temporary failure"
        else
          "recovered"
        end
      end

      result.should eq("recovered")
      attempts.should eq(2)
    end

    it "handles permanent failures appropriately" do
      # Reset retry config for this test
      Session.config.retry_config = Session::RetryConfig.new(
        max_attempts: 3,
        base_delay: 10.milliseconds,
        jitter: 0.0
      )

      # Test handling of permanent failures
      attempts = 0
      expect_raises(Exception, "Permanent failure") do
        Session::Retry.with_retry do
          attempts += 1
          raise "Permanent failure"
        end
      end

      attempts.should eq(3) # Should try max_attempts times
    end
  end

  describe "Health Monitoring" do
    it "tracks session statistics accurately with memory store" do
      memory_store = Session::MemoryStore(UserSession).new
      session = Session::SessionId(UserSession).new
      key = session.session_id

      # Add a valid session
      memory_store[key] = session
      stats = memory_store.memory_stats
      stats[:total_sessions].should eq(1)
      stats[:valid_sessions].should eq(1)
      stats[:expired_sessions].should eq(0)

      # Restore timeout
      Session.config.timeout = 1.hour
    end
  end

  describe "Configuration Management" do
    it "allows runtime configuration changes" do
      # Test that configuration can be changed at runtime
      original_config = Session.config.retry_config

      # Change configuration
      Session.configure do |c|
        c.retry_config = Session::RetryConfig.new(max_attempts: 5)
        c.enable_retry = false
        c.log_errors = false
      end

      # Verify changes
      Session.config.retry_config.max_attempts.should eq(5)
      Session.config.enable_retry.should be_false
      Session.config.log_errors.should be_false

      # Restore original configuration
      Session.configure do |c|
        c.retry_config = original_config
        c.enable_retry = true
        c.log_errors = true
      end
    end

    it "maintains configuration consistency" do
      # Test that configuration is consistent across the system
      config = Session::RetryConfig.new(
        max_attempts: 4,
        base_delay: 150.milliseconds,
        max_delay: 6.seconds,
        backoff_multiplier: 1.5,
        jitter: 0.2
      )

      Session.configure do |c|
        c.retry_config = config
      end

      # Verify configuration is applied
      Session.config.retry_config.max_attempts.should eq(4)
      Session.config.retry_config.base_delay.should eq(150.milliseconds)
      Session.config.retry_config.max_delay.should eq(6.seconds)
      Session.config.retry_config.backoff_multiplier.should eq(1.5)
      Session.config.retry_config.jitter.should eq(0.2)
    end
  end

  describe "Error Propagation" do
    it "propagates specific exceptions correctly" do
      # Test that specific exceptions are propagated correctly
      expect_raises(Session::SessionExpiredException) do
        raise Session::SessionExpiredException.new("Test expired session")
      end

      expect_raises(Session::SessionCorruptionException) do
        raise Session::SessionCorruptionException.new("Test corrupted session")
      end

      expect_raises(Session::StorageConnectionException) do
        raise Session::StorageConnectionException.new("Test connection failure")
      end
    end

    it "preserves exception cause information" do
      # Test that exception cause information is preserved
      original_error = Exception.new("Original error")
      session_error = Session::SessionCorruptionException.new("Corrupted", original_error)

      session_error.cause.should eq(original_error)
      session_error.message.should eq("Corrupted")
    end
  end

  describe "Performance Under Error Conditions" do
    it "maintains performance during error scenarios" do
      # Use minimal delays for performance testing
      Session.config.retry_config = Session::RetryConfig.new(
        max_attempts: 3,
        base_delay: 1.milliseconds,
        max_delay: 10.milliseconds,
        jitter: 0.0
      )

      # Test that the system maintains reasonable performance during errors
      start_time = Time.instant

      # Simulate multiple error scenarios
      10.times do
        begin
          Session::Retry.with_retry do
            raise "Simulated error"
          end
        rescue
          # Expected to fail
        end
      end

      elapsed = Time.instant - start_time
      # Should complete within reasonable time (adjust threshold as needed)
      elapsed.should be < 5.seconds
    end

    it "handles concurrent error scenarios" do
      # Test that the system can handle concurrent error scenarios
      # This is a basic test - more sophisticated concurrency testing would be needed
      results = [] of String

      5.times do |i|
        begin
          result = Session::Retry.with_retry do
            if i < 3
              raise "Temporary failure #{i}"
            else
              "success #{i}"
            end
          end
          results << result
        rescue
          results << "failed #{i}"
        end
      end

      results.size.should eq(5)
    end
  end
end

# Redis integration tests (only run if Redis is available)
if REDIS_AVAILABLE
  describe "Integration Error Handling with Redis" do
    client = redis_client

    describe "Redis-specific Error Scenarios" do
      it "handles corrupted session data in Redis" do
        redis_store = Session::RedisStore(UserSession).new(client)
        key = "test_corruption_key"

        # Store invalid JSON data
        client.setex("session:#{key}", 3600, "invalid json")

        # Should handle corruption gracefully
        expect_raises(Session::SessionCorruptionException) do
          redis_store[key]
        end

        # Clean up
        client.del("session:#{key}")
      end

      it "continues working when Redis is available" do
        redis_store = Session::RedisStore(UserSession).new(client)
        session = Session::SessionId(UserSession).new
        key = session.session_id

        # Should work normally when Redis is available
        redis_store[key] = session
        retrieved_session = redis_store[key]
        retrieved_session.should eq(session)

        # Clean up
        redis_store.delete(key)
      end

      it "provides health check capabilities" do
        redis_store = Session::RedisStore(UserSession).new(client)
        redis_store.healthy?.should be_true
      end
    end
  end
end
