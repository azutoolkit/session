# Security Settings

Configure security features to protect session data.

## Encryption Settings

```crystal
Session.configure do |config|
  # Required: Secret key for encryption
  config.secret = ENV["SESSION_SECRET"]

  # Enforce secure secret (raises if using default)
  config.require_secure_secret = true

  # Digest algorithm for HMAC
  config.digest_algorithm = :sha256

  # Allow fallback to SHA1 for migration
  config.digest_fallback = true
end
```

## Key Derivation (PBKDF2)

Enable PBKDF2 for enhanced security:

```crystal
Session.configure do |config|
  config.use_kdf = true
  config.kdf_iterations = 100_000  # OWASP recommended
  config.kdf_salt = "your-unique-salt"
end
```

## Redis Encryption

Encrypt session data at rest in Redis:

```crystal
Session.configure do |config|
  config.encrypt_redis_data = true
end
```

## Client Binding

Bind sessions to client characteristics:

```crystal
Session.configure do |config|
  config.bind_to_ip = true
  config.bind_to_user_agent = true
end
```

## Security Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `secret` | `String` | (default) | Encryption key |
| `require_secure_secret` | `Bool` | `false` | Enforce non-default secret |
| `digest_algorithm` | `Symbol` | `:sha256` | HMAC algorithm |
| `digest_fallback` | `Bool` | `true` | Allow SHA1 fallback |
| `use_kdf` | `Bool` | `false` | Enable PBKDF2 |
| `kdf_iterations` | `Int32` | `100_000` | PBKDF2 iterations |
| `encrypt_redis_data` | `Bool` | `false` | Encrypt Redis data |
| `bind_to_ip` | `Bool` | `false` | Bind to client IP |
| `bind_to_user_agent` | `Bool` | `false` | Bind to User-Agent |
