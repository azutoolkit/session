require "./spec_helper"

describe Message::Verifier do
  describe "#generate and #verify" do
    it "signs and verifies data" do
      verifier = Message::Verifier.new("secret-key")

      signed = verifier.generate("test message")
      verified = verifier.verify(signed)

      verified.should eq "test message"
    end

    it "generates different signatures for different data" do
      verifier = Message::Verifier.new("secret-key")

      signed1 = verifier.generate("message1")
      signed2 = verifier.generate("message2")

      signed1.should_not eq signed2
    end

    it "raises InvalidSignatureError for tampered data" do
      verifier = Message::Verifier.new("secret-key")

      signed = verifier.generate("original")
      tampered = signed + "tampered"

      expect_raises(Message::Verifier::InvalidSignatureError) do
        verifier.verify(tampered)
      end
    end

    it "raises InvalidSignatureError for wrong key" do
      verifier1 = Message::Verifier.new("key1")
      verifier2 = Message::Verifier.new("key2")

      signed = verifier1.generate("test")

      expect_raises(Message::Verifier::InvalidSignatureError) do
        verifier2.verify(signed)
      end
    end
  end

  describe "#verified" do
    it "returns nil for invalid signature" do
      verifier = Message::Verifier.new("secret")

      result = verifier.verified("invalid-data")
      result.should be_nil
    end

    it "returns data for valid signature" do
      verifier = Message::Verifier.new("secret")

      signed = verifier.generate("valid data")
      result = verifier.verified(signed)

      result.should eq "valid data"
    end
  end

  describe "SHA256 digest (default)" do
    it "uses SHA256 by default" do
      verifier = Message::Verifier.new("secret")

      signed = verifier.generate("test")
      verified = verifier.verified(signed)

      verified.should eq "test"
    end
  end

  describe "SHA1 fallback" do
    it "verifies SHA1-signed data with fallback enabled" do
      # Sign with SHA1
      sha1_verifier = Message::Verifier.new("secret", digest: :sha1, fallback_digest: nil)
      signed = sha1_verifier.generate("legacy data")

      # Verify with SHA256 + SHA1 fallback
      sha256_verifier = Message::Verifier.new("secret", digest: :sha256, fallback_digest: :sha1)
      verified = sha256_verifier.verified(signed)

      verified.should eq "legacy data"
    end

    it "rejects SHA1-signed data without fallback" do
      # Sign with SHA1
      sha1_verifier = Message::Verifier.new("secret", digest: :sha1, fallback_digest: nil)
      signed = sha1_verifier.generate("legacy data")

      # Try to verify with SHA256 only (no fallback)
      sha256_verifier = Message::Verifier.new("secret", digest: :sha256, fallback_digest: nil)
      verified = sha256_verifier.verified(signed)

      verified.should be_nil
    end

    it "re-signs with new algorithm after fallback verification" do
      # Sign with SHA1
      sha1_verifier = Message::Verifier.new("secret", digest: :sha1, fallback_digest: nil)
      old_signed = sha1_verifier.generate("migrate me")

      # Verify and re-sign with SHA256
      sha256_verifier = Message::Verifier.new("secret", digest: :sha256, fallback_digest: :sha1)
      data = sha256_verifier.verified(old_signed)
      data.should eq "migrate me"

      new_signed = sha256_verifier.generate(data.not_nil!)

      # New signature should verify with SHA256 only
      sha256_only = Message::Verifier.new("secret", digest: :sha256, fallback_digest: nil)
      sha256_only.verified(new_signed).should eq "migrate me"
    end
  end

  describe "#verify_raw" do
    it "returns raw bytes" do
      verifier = Message::Verifier.new("secret")

      signed = verifier.generate("binary\x00data")
      raw = verifier.verify_raw(signed)

      String.new(raw).should eq "binary\x00data"
    end

    it "raises InvalidSignatureError for invalid signature" do
      verifier = Message::Verifier.new("secret")

      expect_raises(Message::Verifier::InvalidSignatureError) do
        verifier.verify_raw("invalid")
      end
    end

    it "supports SHA1 fallback" do
      sha1_verifier = Message::Verifier.new("secret", digest: :sha1, fallback_digest: nil)
      signed = sha1_verifier.generate("raw data")

      sha256_verifier = Message::Verifier.new("secret", digest: :sha256, fallback_digest: :sha1)
      raw = sha256_verifier.verify_raw(signed)

      String.new(raw).should eq "raw data"
    end
  end

  describe "#valid_message?" do
    it "returns true for valid signature" do
      verifier = Message::Verifier.new("secret")

      # Generate a message and extract data/digest
      signed = verifier.generate("test")
      json_data = Base64.decode_string(signed)
      data, digest = Tuple(String, String).from_json(json_data)

      verifier.valid_message?(data, digest).should be_true
    end

    it "returns false for tampered signature" do
      verifier = Message::Verifier.new("secret")

      signed = verifier.generate("test")
      json_data = Base64.decode_string(signed)
      data, digest = Tuple(String, String).from_json(json_data)

      verifier.valid_message?(data, "wrong-digest").should be_false
    end

    it "returns false for empty data or digest" do
      verifier = Message::Verifier.new("secret")

      verifier.valid_message?("", "digest").should be_false
      verifier.valid_message?("data", "").should be_false
    end
  end
end
