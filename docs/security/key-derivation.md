# Key Derivation

PBKDF2-SHA256 derives the 32-byte AES key from your secret. It does not make a weak or short secret safe: the HMAC
signature on every cookie uses the secret itself, so a guessable secret can be found offline from one cookie whatever
the KDF does. The secret must still be at least 32 random bytes (`openssl rand -hex 32`); a shorter one raises
`Session::InsecureSecretException`.

## Configuration

```crystal
Session.configure do |config|
  config.use_kdf = true
  config.kdf_iterations = 100_000   # OWASP recommended minimum
  config.kdf_salt = "your-unique-salt"
end
```

## How It Works

When `use_kdf` is enabled, `Message::Encryptor` runs `OpenSSL::PKCS5.pbkdf2_hmac` when it is built to derive a 32-byte key from your secret. This derived key is then used for all AES-256-CBC encryption operations instead of the raw secret.

`Session.config.encryptor` reuses its encryptor while the secret, digest and KDF settings stay the same, so PBKDF2 runs once per setting, not per request. Changing any of them (or `SESSION_SECRET`, when no secret is configured) derives the key again on the next use. An `Encryptor` you build yourself derives its key once, in `new`.

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
