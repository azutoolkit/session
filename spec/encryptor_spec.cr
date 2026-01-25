require "./spec_helper"

describe Message::Encryptor do
  describe "basic encryption" do
    it "encrypts and decrypts data" do
      secret = "12345678901234567890123456789012"
      encryptor = Message::Encryptor.new(secret)

      original = "Hello, World!"
      encrypted = encryptor.encrypt_and_sign(original)
      decrypted = String.new(encryptor.verify_and_decrypt(encrypted))

      decrypted.should eq original
      encrypted.should_not eq original
    end

    it "produces different output for same input (due to random IV)" do
      secret = "12345678901234567890123456789012"
      encryptor = Message::Encryptor.new(secret)

      original = "Hello, World!"
      encrypted1 = encryptor.encrypt_and_sign(original)
      encrypted2 = encryptor.encrypt_and_sign(original)

      encrypted1.should_not eq encrypted2
    end
  end

  describe "with SHA256 digest" do
    it "uses SHA256 by default" do
      secret = "12345678901234567890123456789012"
      encryptor = Message::Encryptor.new(secret)

      original = "test data"
      encrypted = encryptor.encrypt_and_sign(original)
      decrypted = String.new(encryptor.verify_and_decrypt(encrypted))

      decrypted.should eq original
    end

    it "works with explicit SHA256" do
      secret = "12345678901234567890123456789012"
      encryptor = Message::Encryptor.new(secret, digest: :sha256)

      original = "test data"
      encrypted = encryptor.encrypt_and_sign(original)
      decrypted = String.new(encryptor.verify_and_decrypt(encrypted))

      decrypted.should eq original
    end
  end

  describe "with SHA1 fallback" do
    it "can decrypt SHA1-signed data with fallback enabled" do
      secret = "12345678901234567890123456789012"

      # Create with SHA1
      sha1_encryptor = Message::Encryptor.new(secret, digest: :sha1, fallback_digest: nil)
      original = "legacy data"
      encrypted = sha1_encryptor.encrypt_and_sign(original)

      # Decrypt with SHA256 + SHA1 fallback
      sha256_encryptor = Message::Encryptor.new(secret, digest: :sha256, fallback_digest: :sha1)
      decrypted = String.new(sha256_encryptor.verify_and_decrypt(encrypted))

      decrypted.should eq original
    end
  end

  describe "with KDF" do
    it "works with KDF enabled" do
      secret = "my-secret-password"
      encryptor = Message::Encryptor.new(
        secret,
        use_kdf: true,
        kdf_iterations: 1000, # Lower for testing
        kdf_salt: "test-salt"
      )

      original = "sensitive data"
      encrypted = encryptor.encrypt_and_sign(original)
      decrypted = String.new(encryptor.verify_and_decrypt(encrypted))

      decrypted.should eq original
    end

    it "produces different ciphertext with different salts" do
      secret = "my-secret-password"

      encryptor1 = Message::Encryptor.new(secret, use_kdf: true, kdf_salt: "salt1")
      encryptor2 = Message::Encryptor.new(secret, use_kdf: true, kdf_salt: "salt2")

      original = "test"
      # Note: Can't directly compare encrypted values due to random IV,
      # but we verify both work independently

      encrypted1 = encryptor1.encrypt_and_sign(original)
      encrypted2 = encryptor2.encrypt_and_sign(original)

      String.new(encryptor1.verify_and_decrypt(encrypted1)).should eq original
      String.new(encryptor2.verify_and_decrypt(encrypted2)).should eq original
    end

    it "cannot decrypt with wrong salt" do
      secret = "my-secret-password"

      encryptor1 = Message::Encryptor.new(secret, use_kdf: true, kdf_salt: "salt1")
      encryptor2 = Message::Encryptor.new(secret, use_kdf: true, kdf_salt: "salt2")

      encrypted = encryptor1.encrypt_and_sign("test")

      expect_raises(Exception) do
        encryptor2.verify_and_decrypt(encrypted)
      end
    end
  end
end
