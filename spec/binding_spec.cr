require "./spec_helper"

describe Session::ClientFingerprint do
  describe ".binding_enabled?" do
    it "returns false when both bindings disabled" do
      Session.config.bind_to_ip = false
      Session.config.bind_to_user_agent = false

      Session::ClientFingerprint.binding_enabled?.should be_false
    end

    it "returns true when IP binding enabled" do
      Session.config.bind_to_ip = true
      Session.config.bind_to_user_agent = false

      Session::ClientFingerprint.binding_enabled?.should be_true
    end

    it "returns true when User-Agent binding enabled" do
      Session.config.bind_to_ip = false
      Session.config.bind_to_user_agent = true

      Session::ClientFingerprint.binding_enabled?.should be_true
    end

    it "returns true when both enabled" do
      Session.config.bind_to_ip = true
      Session.config.bind_to_user_agent = true

      Session::ClientFingerprint.binding_enabled?.should be_true
    end
  end

  describe "#empty?" do
    it "returns true for empty fingerprint" do
      fingerprint = Session::ClientFingerprint.new
      fingerprint.empty?.should be_true
    end

    it "returns false when IP hash set" do
      fingerprint = Session::ClientFingerprint.new(ip_hash: "abc123")
      fingerprint.empty?.should be_false
    end

    it "returns false when User-Agent hash set" do
      fingerprint = Session::ClientFingerprint.new(user_agent_hash: "def456")
      fingerprint.empty?.should be_false
    end
  end

  describe ".from_request" do
    it "captures IP when bind_to_ip enabled" do
      Session.config.bind_to_ip = true
      Session.config.bind_to_user_agent = false

      headers = HTTP::Headers{"X-Forwarded-For" => "192.168.1.1"}
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint = Session::ClientFingerprint.from_request(request)

      fingerprint.ip_hash.should_not be_nil
    end

    it "captures User-Agent when bind_to_user_agent enabled" do
      Session.config.bind_to_ip = false
      Session.config.bind_to_user_agent = true

      headers = HTTP::Headers{"User-Agent" => "Mozilla/5.0"}
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint = Session::ClientFingerprint.from_request(request)

      fingerprint.user_agent_hash.should_not be_nil
    end

    it "captures both when both enabled" do
      Session.config.bind_to_ip = true
      Session.config.bind_to_user_agent = true

      headers = HTTP::Headers{
        "X-Forwarded-For" => "10.0.0.1",
        "User-Agent"      => "TestAgent/1.0",
      }
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint = Session::ClientFingerprint.from_request(request)

      fingerprint.ip_hash.should_not be_nil
      fingerprint.user_agent_hash.should_not be_nil
    end

    it "returns empty fingerprint when bindings disabled" do
      Session.config.bind_to_ip = false
      Session.config.bind_to_user_agent = false

      headers = HTTP::Headers{
        "X-Forwarded-For" => "10.0.0.1",
        "User-Agent"      => "TestAgent/1.0",
      }
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint = Session::ClientFingerprint.from_request(request)

      fingerprint.empty?.should be_true
    end

    it "extracts first IP from X-Forwarded-For" do
      Session.config.bind_to_ip = true

      headers = HTTP::Headers{"X-Forwarded-For" => "1.1.1.1, 2.2.2.2, 3.3.3.3"}
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint = Session::ClientFingerprint.from_request(request)

      # Hash should be of "1.1.1.1" only
      fingerprint.ip_hash.should_not be_nil
    end

    it "uses X-Real-IP as fallback" do
      Session.config.bind_to_ip = true

      headers = HTTP::Headers{"X-Real-IP" => "5.5.5.5"}
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint = Session::ClientFingerprint.from_request(request)

      fingerprint.ip_hash.should_not be_nil
    end
  end

  describe "JSON serialization" do
    it "serializes to JSON" do
      fingerprint = Session::ClientFingerprint.new(
        ip_hash: "ip_hash_value",
        user_agent_hash: "ua_hash_value"
      )

      json = fingerprint.to_json
      json.should contain("ip_hash")
      json.should contain("user_agent_hash")
    end

    it "deserializes from JSON" do
      original = Session::ClientFingerprint.new(
        ip_hash: "ip123",
        user_agent_hash: "ua456"
      )

      json = original.to_json
      restored = Session::ClientFingerprint.from_json(json)

      restored.ip_hash.should eq "ip123"
      restored.user_agent_hash.should eq "ua456"
    end
  end
end

describe Session::SessionBindingException do
  it "includes binding type" do
    ex = Session::SessionBindingException.new("ip")
    ex.binding_type.should eq "ip"
    ex.message.to_s.should contain("ip")
  end

  it "uses custom message" do
    ex = Session::SessionBindingException.new("user_agent", "Custom message")
    ex.message.to_s.should eq "Custom message"
  end
end
