require "./spec_helper"

describe Session::SessionId do
  describe "#touch" do
    it "extends expiration time" do
      Session.config.timeout = 1.hour
      session = Session::SessionId(UserSession).new

      original_expires = session.expires_at
      sleep 10.milliseconds
      session.touch
      new_expires = session.expires_at

      new_expires.should be > original_expires
    end

    it "resets to full timeout duration" do
      Session.config.timeout = 1.hour
      session = Session::SessionId(UserSession).new

      session.touch

      # Should expire approximately 1 hour from now
      time_remaining = session.time_until_expiry
      time_remaining.total_minutes.should be > 59
    end
  end

  describe "#time_until_expiry" do
    it "returns positive time for valid session" do
      Session.config.timeout = 1.hour
      session = Session::SessionId(UserSession).new

      time = session.time_until_expiry
      time.total_seconds.should be > 0
    end

    it "returns zero or positive for expired session" do
      Session.config.timeout = -1.hour
      session = Session::SessionId(UserSession).new

      time = session.time_until_expiry
      time.total_seconds.should eq 0
    end
  end

  describe "#expired?" do
    it "returns false for fresh session" do
      Session.config.timeout = 1.hour
      session = Session::SessionId(UserSession).new

      session.expired?.should be_false
    end

    it "returns true for expired session" do
      Session.config.timeout = -1.second
      session = Session::SessionId(UserSession).new

      session.expired?.should be_true
    end
  end

  describe "#valid?" do
    it "is inverse of expired?" do
      Session.config.timeout = 1.hour
      session = Session::SessionId(UserSession).new

      session.valid?.should eq !session.expired?
    end
  end

  describe "data property" do
    it "allows reading data" do
      session = Session::SessionId(UserSession).new
      session.data.username.should eq "example"
    end

    it "allows modifying data" do
      session = Session::SessionId(UserSession).new
      session.data.username = "changed"
      session.data.username.should eq "changed"
    end

    it "allows replacing data" do
      session = Session::SessionId(UserSession).new
      new_data = UserSession.new
      new_data.username = "replaced"

      session.data = new_data
      session.data.username.should eq "replaced"
    end
  end

  describe "JSON serialization" do
    it "serializes to JSON" do
      session = Session::SessionId(UserSession).new
      json = session.to_json

      json.should contain("session_id")
      json.should contain("created_at")
      json.should contain("expires_at")
      json.should contain("data")
    end

    it "deserializes from JSON" do
      original = Session::SessionId(UserSession).new
      original.data.username = "test_user"

      json = original.to_json
      restored = Session::SessionId(UserSession).from_json(json)

      restored.session_id.should eq original.session_id
      restored.data.username.should eq "test_user"
    end
  end
end
