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
  # The secret is read from SESSION_SECRET (random per process without it, outside production and staging)
  config.digest_algorithm = :sha256           # HMAC algorithm
  config.digest_fallback = true               # Allow SHA1 fallback for migration
  config.require_secure_secret = true         # Raise on a missing, published or short secret
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

- At least 32 bytes, with or without `use_kdf` (the HMAC signature uses the secret itself): a shorter one raises
  `InsecureSecretException`, from `Session.configure` when the store encrypts with it
- Unset, `secret` is `SESSION_SECRET`. Without that, `InsecureSecretException` where `require_secure_secret` holds
  (production and staging by default, read from `CRYSTAL_ENV` each time the secret is read), and a random per-process
  key with one warning elsewhere. With a `CookieStore`, or `encrypt_redis_data`, `Session::SessionHandler` then fails every request with `Session::InsecureSecretException` (a 500, logged by the server) instead of answering without a working session; a store that does not encrypt never reads the secret, so nothing is raised.
- The secret older releases used by default (`Configuration::DEFAULT_SECRET`) is public: set explicitly, it is refused
  where `require_secure_secret` holds and warned about elsewhere

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `secret` | `String` | `SESSION_SECRET` | Encryption key (32+ bytes) |
| `require_secure_secret` | `Bool` | production, staging | Raise on a missing or published secret |
| `digest_algorithm` | `Symbol` | `:sha256` | HMAC algorithm |
| `digest_fallback` | `Bool` | `true` | Allow SHA1 fallback |
| `encrypt_redis_data` | `Bool` | `false` | Encrypt data in Redis |

## See Also

- [Key Derivation](key-derivation.md) -- PBKDF2 for enhanced key security
- [Security Settings](../configuration/security.md)
