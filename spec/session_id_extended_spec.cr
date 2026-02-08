require "./spec_helper"

describe UserSession do
  describe "#touch" do
    it "extends expiration time" do
      Session.config.timeout = 1.hour
      session = UserSession.new

      original_expires = session.expires_at
      sleep 10.milliseconds
      session.touch
      new_expires = session.expires_at

      new_expires.should be > original_expires
    end

    it "resets to full timeout duration" do
      Session.config.timeout = 1.hour
      session = UserSession.new

      session.touch

      # Should expire approximately 1 hour from now
      time_remaining = session.time_until_expiry
      time_remaining.total_minutes.should be > 59
    end
  end

  describe "#time_until_expiry" do
    it "returns positive time for valid session" do
      Session.config.timeout = 1.hour
      session = UserSession.new

      time = session.time_until_expiry
      time.total_seconds.should be > 0
    end

    it "returns zero or positive for expired session" do
      Session.config.timeout = -1.hour
      session = UserSession.new

      time = session.time_until_expiry
      time.total_seconds.should eq 0
    end
  end

  describe "#expired?" do
    it "returns false for fresh session" do
      Session.config.timeout = 1.hour
      session = UserSession.new

      session.expired?.should be_false
    end

    it "returns true for expired session" do
      Session.config.timeout = -1.second
      session = UserSession.new

      session.expired?.should be_true
    end
  end

  describe "#valid?" do
    it "is inverse of expired?" do
      Session.config.timeout = 1.hour
      session = UserSession.new

      session.valid?.should eq !session.expired?
    end
  end

  describe "data property" do
    it "allows reading data" do
      session = UserSession.new
      session.username.should eq "example"
    end

    it "allows modifying data" do
      session = UserSession.new
      session.username = "changed"
      session.username.should eq "changed"
    end

    it "allows replacing data" do
      session = UserSession.new
      session.username = "replaced"
      session.username.should eq "replaced"
    end
  end

  describe "JSON serialization" do
    it "serializes to JSON" do
      session = UserSession.new
      json = session.to_json

      json.should contain("session_id")
      json.should contain("created_at")
      json.should contain("expires_at")
      json.should contain("authenticated")
    end

    it "deserializes from JSON" do
      original = UserSession.new
      original.username = "test_user"

      json = original.to_json
      restored = UserSession.from_json(json)

      restored.session_id.should eq original.session_id
      restored.username.should eq "test_user"
    end
  end
end
