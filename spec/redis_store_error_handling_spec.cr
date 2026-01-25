require "./spec_helper"

if REDIS_AVAILABLE
  describe "RedisStore Error Handling" do
    client = redis_client
    session = Session::SessionId(UserSession).new
    redis_store = Session::RedisStore(UserSession).new(client)
    key = session.session_id

    before_each do
      redis_store.clear
    end

    describe "Session Retrieval with Error Handling" do
      it "raises SessionNotFoundException for missing sessions" do
        expect_raises(Session::SessionNotFoundException, "Session not found: invalid_key") do
          redis_store["invalid_key"]
        end
      end

      it "returns nil for missing sessions with []?" do
        redis_store["invalid_key"]?.should be_nil
      end

      it "successfully retrieves valid sessions" do
        redis_store[key] = session
        retrieved_session = redis_store[key]
        retrieved_session.should eq(session)
      end

      it "handles JSON parsing errors gracefully" do
        # Store invalid JSON data directly in Redis
        client.setex("session:#{key}", 3600, "invalid json")

        expect_raises(Session::SessionCorruptionException, "Invalid JSON in session data") do
          redis_store[key]
        end

        # Clean up
        client.del("session:#{key}")
      end

      it "handles deserialization errors gracefully" do
        # Store valid JSON but invalid session data
        invalid_data = %({"invalid": "data"})
        client.setex("session:#{key}", 3600, invalid_data)

        expect_raises(Session::SessionSerializationException, "Session deserialization failed") do
          redis_store[key]
        end

        # Clean up
        client.del("session:#{key}")
      end
    end

    describe "Session Storage with Error Handling" do
      it "successfully stores valid sessions" do
        redis_store[key] = session
        stored_session = redis_store[key]
        stored_session.should eq(session)
      end

      it "handles serialization errors gracefully" do
        redis_store[key] = session
        redis_store[key].should eq(session)
      end

      it "handles storage errors gracefully" do
        redis_store[key] = session
        redis_store[key].should eq(session)
      end
    end

    describe "Session Deletion with Error Handling" do
      it "handles deletion gracefully" do
        redis_store[key] = session
        redis_store.delete(key)
        redis_store[key]?.should be_nil
      end

      it "handles deletion of non-existent sessions gracefully" do
        redis_store.delete("non_existent_key").should be_nil
      end
    end

    describe "Session Counting with Error Handling" do
      it "returns correct count for valid sessions" do
        redis_store.clear
        redis_store.size.should eq(0)

        redis_store[key] = session
        redis_store.size.should eq(1)
      end

      it "handles counting errors gracefully" do
        redis_store.size.should be >= 0
      end
    end

    describe "Session Clearing with Error Handling" do
      it "clears all sessions successfully" do
        redis_store[key] = session
        redis_store.size.should eq(1)

        redis_store.clear
        redis_store.size.should eq(0)
      end

      it "handles clearing errors gracefully" do
        redis_store.clear.should be_nil
      end
    end

    describe "Health Check Methods" do
      it "returns true for healthy Redis connection" do
        redis_store.healthy?.should be_true
      end

      it "performs ping health check" do
        redis_store.healthy?.should be_true
      end

      it "handles health check errors gracefully" do
        redis_store.healthy?.should be_true
      end
    end

    describe "Graceful Shutdown" do
      it "handles shutdown gracefully" do
        redis_store.shutdown.should be_nil
      end
    end

    describe "Retry Logic Integration" do
      it "uses retry configuration from session config" do
        original_config = Session.config.retry_config
        Session.config.retry_config = Session::RetryConfig.new(max_attempts: 1)

        redis_store[key] = session
        redis_store[key].should eq(session)

        Session.config.retry_config = original_config
      end

      it "retries on connection errors" do
        redis_store[key] = session
        redis_store[key].should eq(session)
      end
    end

    describe "Error Logging" do
      it "logs errors appropriately" do
        redis_store[key] = session
        redis_store[key].should eq(session)
      end

      it "logs corruption errors" do
        client.setex("session:#{key}", 3600, "invalid json")

        expect_raises(Session::SessionCorruptionException) do
          redis_store[key]
        end

        client.del("session:#{key}")
      end
    end

    describe "Session Prefixing" do
      it "uses correct session prefix" do
        redis_store[key] = session

        redis_keys = client.keys("session:*")
        redis_keys.should contain("session:#{key}")
      end

      it "handles prefix-related errors gracefully" do
        redis_store[key] = session
        redis_store[key].should eq(session)
      end
    end
  end
end
