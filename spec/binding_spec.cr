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

  describe "#validate!" do
    it "passes when IP matches" do
      Session.config.bind_to_ip = true
      Session.config.bind_to_user_agent = false

      headers = HTTP::Headers{"X-Forwarded-For" => "10.0.0.1"}
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint = Session::ClientFingerprint.from_request(request)

      # Same IP should not raise
      fingerprint.validate!(request)
    end

    it "raises SessionBindingException when IP mismatches" do
      Session.config.bind_to_ip = true
      Session.config.bind_to_user_agent = false

      original_headers = HTTP::Headers{"X-Forwarded-For" => "10.0.0.1"}
      original_request = HTTP::Request.new("GET", "/", original_headers)

      fingerprint = Session::ClientFingerprint.from_request(original_request)

      different_headers = HTTP::Headers{"X-Forwarded-For" => "10.0.0.2"}
      different_request = HTTP::Request.new("GET", "/", different_headers)

      expect_raises(Session::SessionBindingException, "Session IP address mismatch") do
        fingerprint.validate!(different_request)
      end
    end

    it "passes when User-Agent matches" do
      Session.config.bind_to_ip = false
      Session.config.bind_to_user_agent = true

      headers = HTTP::Headers{"User-Agent" => "TestAgent/1.0"}
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint = Session::ClientFingerprint.from_request(request)

      fingerprint.validate!(request)
    end

    it "raises SessionBindingException when User-Agent mismatches" do
      Session.config.bind_to_ip = false
      Session.config.bind_to_user_agent = true

      original_headers = HTTP::Headers{"User-Agent" => "TestAgent/1.0"}
      original_request = HTTP::Request.new("GET", "/", original_headers)

      fingerprint = Session::ClientFingerprint.from_request(original_request)

      different_headers = HTTP::Headers{"User-Agent" => "DifferentAgent/2.0"}
      different_request = HTTP::Request.new("GET", "/", different_headers)

      expect_raises(Session::SessionBindingException, "Session User-Agent mismatch") do
        fingerprint.validate!(different_request)
      end
    end

    it "skips IP check when bind_to_ip is false" do
      Session.config.bind_to_ip = false
      Session.config.bind_to_user_agent = false

      # Manually create a fingerprint with an ip_hash
      fingerprint = Session::ClientFingerprint.new(ip_hash: "some_hash")

      # Different IP should not raise since binding is disabled
      headers = HTTP::Headers{"X-Forwarded-For" => "99.99.99.99"}
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint.validate!(request)
    end

    it "skips UA check when bind_to_user_agent is false" do
      Session.config.bind_to_ip = false
      Session.config.bind_to_user_agent = false

      fingerprint = Session::ClientFingerprint.new(user_agent_hash: "some_hash")

      headers = HTTP::Headers{"User-Agent" => "Anything"}
      request = HTTP::Request.new("GET", "/", headers)

      fingerprint.validate!(request)
    end

    it "raises when request has no IP header but fingerprint has ip_hash" do
      Session.config.bind_to_ip = true
      Session.config.bind_to_user_agent = false

      original_headers = HTTP::Headers{"X-Forwarded-For" => "10.0.0.1"}
      original_request = HTTP::Request.new("GET", "/", original_headers)
      fingerprint = Session::ClientFingerprint.from_request(original_request)

      # Request with no IP headers
      request = HTTP::Request.new("GET", "/")

      expect_raises(Session::SessionBindingException, "Session IP address mismatch") do
        fingerprint.validate!(request)
      end
    end

    it "raises when request has no User-Agent but fingerprint has ua_hash" do
      Session.config.bind_to_ip = false
      Session.config.bind_to_user_agent = true

      original_headers = HTTP::Headers{"User-Agent" => "TestAgent/1.0"}
      original_request = HTTP::Request.new("GET", "/", original_headers)
      fingerprint = Session::ClientFingerprint.from_request(original_request)

      # Request with no User-Agent header
      request = HTTP::Request.new("GET", "/")

      expect_raises(Session::SessionBindingException, "Session User-Agent mismatch") do
        fingerprint.validate!(request)
      end
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
