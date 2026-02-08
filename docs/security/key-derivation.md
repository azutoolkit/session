# Key Derivation

PBKDF2-SHA256 derives a strong 32-byte encryption key from your secret, adding protection against brute-force attacks on weak or short secrets.

## Configuration

```crystal
Session.configure do |config|
  config.use_kdf = true
  config.kdf_iterations = 100_000   # OWASP recommended minimum
  config.kdf_salt = "your-unique-salt"
end
```

## How It Works

When `use_kdf` is enabled, the library runs `OpenSSL::PKCS5.pbkdf2_hmac` at initialization to derive a 32-byte key from your secret. This derived key is then used for all AES-256-CBC encryption operations instead of the raw secret.

The derived key is computed once and cached, so there is no per-request performance cost.

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `use_kdf` | `Bool` | `false` | Enable PBKDF2 key derivation |
| `kdf_iterations` | `Int32` | `100_000` | PBKDF2 iteration count |
| `kdf_salt` | `String` | `"session_kdf_salt"` | Salt for key derivation |

## Preset Defaults

| Preset | KDF Enabled | Iterations |
|--------|-------------|------------|
| `:development` | No | -- |
| `:testing` | No | -- |
| `:production` | Yes | 100,000 |
| `:high_security` | Yes | 100,000 |
| `:clustered` | Yes | 100,000 |

## See Also

- [Encryption & Signing](encryption.md)
- [Security Settings](../configuration/security.md)
