# Client Binding

Bind sessions to client fingerprints (IP address and/or User-Agent) to prevent session hijacking. A stolen session cookie won't work from a different client.

## Configuration

```crystal
Session.configure do |config|
  config.bind_to_ip = true
  config.bind_to_user_agent = true
end
```

## How It Works

When binding is enabled, `ClientFingerprint.from_request` extracts the client's IP and/or User-Agent, SHA-256 hashes them, and stores the hashes with the session. On each subsequent request, `validate!` compares the current client's fingerprint against the stored one. A mismatch raises `SessionBindingException`.

## IP Extraction

The client IP is extracted in order of priority:

1. `X-Forwarded-For` header (first IP, for proxied requests)
2. `X-Real-IP` header
3. Direct connection address (if available)

This ensures correct behavior behind reverse proxies and load balancers.

## SessionHandler Integration

The `SessionHandler` automatically validates client binding on session load. If validation fails, the corrupted/mismatched session is cleared and a new session is created. No manual validation is required.

## Trade-offs

| Binding | Protection | Considerations |
|---------|------------|----------------|
| IP | Prevents use from different networks | May break for mobile users switching between WiFi/cellular, or VPN users |
| User-Agent | Prevents use from different browsers | Less disruptive; User-Agent rarely changes mid-session |
| Both | Maximum protection | Use with `:high_security` preset |

For most applications, User-Agent binding alone provides good protection with minimal friction. Add IP binding only when the risk of session hijacking outweighs the risk of legitimate users being logged out.

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `bind_to_ip` | `Bool` | `false` | Bind sessions to client IP |
| `bind_to_user_agent` | `Bool` | `false` | Bind sessions to User-Agent |

## See Also

- [Encryption & Signing](encryption.md)
- [Security Settings](../configuration/security.md)
