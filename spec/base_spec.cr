require "./spec_helper"

describe Session::Base do
  describe "#==" do
    it "returns true for sessions with the same session_id" do
      session = UserSession.new
      json = session.to_json
      restored = UserSession.from_json(json)

      (session == restored).should be_true
    end

    it "returns false for sessions with different session_ids" do
      session1 = UserSession.new
      session2 = UserSession.new

      (session1 == session2).should be_false
    end
  end

  describe "#created_at" do
    it "is set on initialization" do
      before = Time.local
      session = UserSession.new
      after = Time.local

      session.created_at.should be >= before
      session.created_at.should be <= after
    end

    it "survives JSON round-trip at second precision" do
      session = UserSession.new
      restored = UserSession.from_json(session.to_json)

      # JSON serialization truncates sub-second precision
      restored.created_at.to_unix.should eq session.created_at.to_unix
    end
  end

  describe "#expires_at" do
    it "survives JSON round-trip at second precision" do
      session = UserSession.new
      restored = UserSession.from_json(session.to_json)

      # JSON serialization truncates sub-second precision
      restored.expires_at.to_unix.should eq session.expires_at.to_unix
    end

    it "reflects configured timeout" do
      Session.config.timeout = 2.hours
      session = UserSession.new

      # Should expire approximately 2 hours from now
      time_remaining = session.expires_at - Time.local
      time_remaining.total_hours.should be > 1.9
      time_remaining.total_hours.should be <= 2.0
    end
  end

  describe "#session_id" do
    it "is a UUID string" do
      session = UserSession.new
      session.session_id.should match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "is unique per session" do
      ids = (1..10).map { UserSession.new.session_id }
      ids.uniq.size.should eq 10
    end
  end
end
