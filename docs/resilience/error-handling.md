# Error Handling

Session uses specific exception types for precise error handling and graceful degradation.

## Exception Hierarchy

| Exception | Properties | Raised When |
|-----------|------------|-------------|
| `SessionExpiredException` | -- | Accessing an expired session |
| `SessionNotFoundException` | -- | Session ID not found in store |
| `SessionCorruptionException` | -- | Invalid or corrupted session data |
| `StorageConnectionException` | -- | Redis/storage connection failure |
| `SessionValidationException` | -- | General validation failure |
| `SessionSerializationException` | -- | JSON serialization/deserialization error |
| `SessionEncryptionException` | -- | Encryption or decryption failure |
| `CookieSizeExceededException` | `actual_size`, `max_size` | Cookie exceeds 4KB limit |
| `SessionBindingException` | `binding_type` | Client fingerprint mismatch |
| `InsecureSecretException` | -- | Default secret with `require_secure_secret` |
| `CircuitOpenException` | `time_until_retry` | Circuit breaker is open |
| `ConnectionPoolTimeoutException` | -- | Pool checkout timeout |
| `ClusterException` | -- | General cluster failure |
| `ClusterConnectionException` | -- | Cluster connection failure |
| `ClusterSubscriptionException` | -- | Pub/Sub subscription failure |

All exceptions accept an optional `cause : Exception?` parameter for chaining underlying errors.

## Catching Exceptions

```crystal
begin
  session = store[session_id]
rescue ex : Session::SessionExpiredException
  # Session timed out -- redirect to login
rescue ex : Session::SessionNotFoundException
  # Session ID not in store -- create new session
rescue ex : Session::SessionCorruptionException
  # Data corrupted -- clear and recreate
rescue ex : Session::StorageConnectionException
  # Redis down -- degrade gracefully
rescue ex : Exception
  # Unexpected error
end
```

## Graceful Degradation

The store provides safe alternatives that don't raise:

- `store[key]?` returns `nil` instead of raising on missing/expired/corrupted sessions
- `store.delete` logs errors but does not re-raise
- `store.size` returns `0` on connection failure

## SessionHandler Behavior

The HTTP `SessionHandler` catches all exceptions during session loading and saving:

- **Expired/missing sessions** -- A new session is created transparently
- **Corrupted sessions** -- The session is cleared and recreated
- **Connection errors** -- Logged; the request continues without session functionality
- **Cookie save errors** -- Logged; the response is not interrupted

This ensures session errors never crash your application.

## Configuration

```crystal
Session.configure do |config|
  config.enable_retry = true            # Retry transient failures
  config.log_errors = true              # Log all errors
  config.fail_fast_on_corruption = true # Raise immediately on corruption
end
```

## See Also

- [Exceptions API](../api/exceptions.md) -- Complete exception reference
- [Circuit Breaker](circuit-breaker.md)
- [Retry Logic](retry-logic.md)
