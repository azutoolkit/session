# Encryption & Signing

Session protects data integrity and confidentiality using AES-256-CBC encryption with HMAC signing.

## How It Works

1. **Encrypt**: Data is encrypted with AES-256-CBC using a random IV per operation
2. **Sign**: The ciphertext is signed with HMAC-SHA256 to detect tampering
3. **Encode**: The signed ciphertext is Base64-encoded for safe transport

Decryption reverses the process: decode, verify HMAC signature, then decrypt. This encrypt-then-sign approach prevents padding oracle attacks.

## Configuration

```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]       # 32+ characters recommended
  config.digest_algorithm = :sha256           # HMAC algorithm
  config.digest_fallback = true               # Allow SHA1 fallback for migration
  config.require_secure_secret = true         # Raise if using default secret
end
```

## Cookie Store

CookieStore always encrypts session data. Every cookie write encrypts and signs; every read verifies and decrypts. No additional configuration needed.

## Redis Store

Redis data is stored as plain JSON by default. Enable encryption at rest:

```crystal
Session.configure do |config|
  config.encrypt_redis_data = true
end
```

When enabled, session data is encrypted before writing to Redis and decrypted on read.

## HMAC Digest Migration

The default digest is `:sha256`. If you're migrating from an older version that used SHA1:

1. Keep `digest_fallback = true` (default) -- sessions signed with SHA1 are accepted and re-signed with SHA256 on next save
2. A deprecation warning is logged once when a SHA1 fallback occurs
3. After all sessions have been re-signed, disable fallback: `config.digest_fallback = false`

## Secret Key Requirements

- Minimum 32 characters for AES-256
- Set `require_secure_secret = true` in production to raise `InsecureSecretException` if the default secret is used
- Without `require_secure_secret`, a warning is logged once on first use of the default secret

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `secret` | `String` | (default) | Encryption key (32+ chars) |
| `require_secure_secret` | `Bool` | `false` | Raise on default secret |
| `digest_algorithm` | `Symbol` | `:sha256` | HMAC algorithm |
| `digest_fallback` | `Bool` | `true` | Allow SHA1 fallback |
| `encrypt_redis_data` | `Bool` | `false` | Encrypt data in Redis |

## See Also

- [Key Derivation](key-derivation.md) -- PBKDF2 for enhanced key security
- [Security Settings](../configuration/security.md)
