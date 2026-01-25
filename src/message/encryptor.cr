require "json"
require "openssl"

module Message
  class Encryptor
    getter verifier : Verifier

    # AES-256 requires a 32-byte key
    KEY_LENGTH = 32

    # Derived key from KDF (when use_kdf is enabled)
    @derived_key : Bytes? = nil

    def initialize(
      @secret : String,
      @cipher_algorithm = "aes-256-cbc",
      @digest : Symbol = :sha256,
      @fallback_digest : Symbol? = :sha1,
      @use_kdf : Bool = false,
      @kdf_iterations : Int32 = 100_000,
      @kdf_salt : String = "session_kdf_salt"
    )
      @verifier = Verifier.new(@secret, digest: @digest, fallback_digest: @fallback_digest)
      @block_size = 16
      @derived_key = derive_key if @use_kdf
    end

    # Encrypt and sign a message. We need to sign the message in order to avoid
    # padding attacks. Reference: http://www.limited-entropy.com/padding-oracle-attacks.
    def encrypt_and_sign(value : Slice(UInt8)) : String
      verifier.generate(encrypt(value))
    end

    def encrypt_and_sign(value : String) : String
      encrypt_and_sign(value.to_slice)
    end

    # Verify and Decrypt a message. We need to verify the message in order to
    # avoid padding attacks. Reference: http://www.limited-entropy.com/padding-oracle-attacks.
    def verify_and_decrypt(value : String) : Bytes
      decrypt(verifier.verify_raw(value))
    end

    def encrypt(value) : Bytes
      cipher = OpenSSL::Cipher.new(@cipher_algorithm)
      cipher.encrypt
      set_cipher_key(cipher)

      # Rely on OpenSSL for the initialization vector
      iv = cipher.random_iv

      encrypted_data = IO::Memory.new
      encrypted_data.write(cipher.update(value))
      encrypted_data.write(cipher.final)
      encrypted_data.write(iv)

      encrypted_data.to_slice
    end

    def decrypt(value : Bytes) : Bytes
      cipher = OpenSSL::Cipher.new(@cipher_algorithm)
      data = value[0, value.size - @block_size]
      iv = value[value.size - @block_size, @block_size]

      cipher.decrypt
      set_cipher_key(cipher)
      cipher.iv = iv

      decrypted_data = IO::Memory.new
      decrypted_data.write cipher.update(data)
      decrypted_data.write cipher.final
      decrypted_data.to_slice
    end

    private def set_cipher_key(cipher)
      if @use_kdf
        if derived = @derived_key
          cipher.key = derived
        else
          cipher.key = @secret
        end
      else
        cipher.key = @secret
      end
    end

    # Derive a key from the secret using PBKDF2-SHA256
    private def derive_key : Bytes
      OpenSSL::PKCS5.pbkdf2_hmac(
        @secret,
        @kdf_salt,
        iterations: @kdf_iterations,
        algorithm: OpenSSL::Algorithm::SHA256,
        key_size: KEY_LENGTH
      )
    end
  end
end
