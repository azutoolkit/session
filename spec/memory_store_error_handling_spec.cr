require "./spec_helper"

describe "MemoryStore Error Handling" do
  session = Session::SessionId(UserSession).new
  memory_store = Session::MemoryStore(UserSession).new
  key = session.session_id

  before_each do
    memory_store.clear
    # Ensure default timeout
    Session.config.timeout = 1.hour
  end

  describe "Session Retrieval with Error Handling" do
    it "raises SessionNotFoundException for missing sessions" do
      expect_raises(Session::SessionNotFoundException, "Session not found: invalid_key") do
        memory_store["invalid_key"]
      end
    end

    it "raises SessionExpiredException for expired sessions" do
      # Create and store a valid session first
      Session.config.timeout = 1.hour
      test_session = Session::SessionId(UserSession).new
      test_key = test_session.session_id
      memory_store[test_key] = test_session

      # Now manually expire the session by modifying the internal hash
      # We need to create an expired session and directly insert it
      memory_store.sessions.clear

      # Create session, store directly bypassing validation
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      expired_key = expired_session.session_id
      memory_store.sessions[expired_key] = expired_session

      expect_raises(Session::SessionExpiredException) do
        memory_store[expired_key]
      end

      # Restore timeout
      Session.config.timeout = 1.hour
    end

    it "returns nil for missing sessions with []?" do
      memory_store["invalid_key"]?.should be_nil
    end

    it "returns nil for expired sessions with []?" do
      # Create session and store directly to bypass validation
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      expired_key = expired_session.session_id
      memory_store.sessions[expired_key] = expired_session

      memory_store[expired_key]?.should be_nil

      # Restore timeout
      Session.config.timeout = 1.hour
    end

    it "automatically cleans up expired sessions on retrieval" do
      # Create session and store directly to bypass validation
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      expired_key = expired_session.session_id
      memory_store.sessions[expired_key] = expired_session

      # Try to retrieve it (should fail and clean up)
      expect_raises(Session::SessionExpiredException) do
        memory_store[expired_key]
      end

      # Session should be cleaned up from internal hash
      memory_store.sessions[expired_key]?.should be_nil

      # Restore timeout
      Session.config.timeout = 1.hour
    end
  end

  describe "Session Storage with Validation" do
    it "raises SessionValidationException for expired sessions" do
      # Create an expired session
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      expired_key = expired_session.session_id

      expect_raises(Session::SessionValidationException) do
        memory_store[expired_key] = expired_session
      end

      # Restore timeout
      Session.config.timeout = 1.hour
    end

    it "successfully stores valid sessions" do
      Session.config.timeout = 1.hour
      memory_store[key] = session
      memory_store[key].should eq(session)
    end
  end

  describe "Session Counting" do
    it "only counts valid sessions" do
      # Add a valid session
      Session.config.timeout = 1.hour
      valid_session = Session::SessionId(UserSession).new
      memory_store[valid_session.session_id] = valid_session
      memory_store.size.should eq(1)

      # Add an expired session directly to internal storage
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      memory_store.sessions[expired_session.session_id] = expired_session

      # Size should still only count valid sessions
      Session.config.timeout = 1.hour  # Reset before count
      memory_store.size.should eq(1)
    end

    it "handles counting errors gracefully" do
      memory_store.size.should be >= 0
    end
  end

  describe "Cleanup Methods" do
    it "cleans up expired sessions" do
      # Store a valid session
      Session.config.timeout = 1.hour
      valid_session = Session::SessionId(UserSession).new
      memory_store[valid_session.session_id] = valid_session

      # Add an expired session directly
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      memory_store.sessions[expired_session.session_id] = expired_session

      # Reset timeout before cleanup
      Session.config.timeout = 1.hour

      # Cleanup should remove expired session
      expired_count = memory_store.cleanup_expired
      expired_count.should eq(1)

      # Only valid session should remain
      memory_store.sessions.size.should eq(1)
    end

    it "handles cleanup errors gracefully" do
      memory_store.cleanup_expired.should be >= 0
    end
  end

  describe "Memory Statistics" do
    it "provides accurate session statistics" do
      # Start fresh
      memory_store.clear
      Session.config.timeout = 1.hour

      # Add a valid session
      valid_session = Session::SessionId(UserSession).new
      memory_store[valid_session.session_id] = valid_session

      # Add an expired session directly
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      memory_store.sessions[expired_session.session_id] = expired_session

      # Reset timeout before checking stats
      Session.config.timeout = 1.hour

      stats = memory_store.memory_stats
      stats[:total_sessions].should eq(2)
      stats[:valid_sessions].should eq(1)
      stats[:expired_sessions].should eq(1)
    end

    it "handles statistics errors gracefully" do
      stats = memory_store.memory_stats
      stats.should be_a(NamedTuple(total_sessions: Int32, valid_sessions: Int32, expired_sessions: Int32))
    end
  end

  describe "Error Handling in Operations" do
    it "handles delete errors gracefully" do
      memory_store.delete("non_existent_key").should be_nil
    end

    it "handles clear errors gracefully" do
      # clear returns the cleared hash (which may be empty)
      memory_store.clear
      memory_store.size.should eq(0)
    end
  end
end
