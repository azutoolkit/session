# Exceptions

Complete exception reference for the Session library. All exceptions accept an optional `cause : Exception?` for wrapping underlying errors.

## Exception Reference

| Exception | Parent | Properties | Default Message |
|-----------|--------|------------|-----------------|
| `SessionExpiredException` | `Exception` | -- | "Session has expired" |
| `SessionNotFoundException` | `Exception` | -- | "Session not found" |
| `SessionCorruptionException` | `Exception` | -- | "Session data is corrupted" |
| `StorageConnectionException` | `Exception` | -- | "Storage connection failed" |
| `SessionValidationException` | `Exception` | -- | "Session validation failed" |
| `SessionSerializationException` | `Exception` | -- | "Session serialization failed" |
| `SessionEncryptionException` | `Exception` | -- | "Session encryption/decryption failed" |
| `CookieSizeExceededException` | `Exception` | `actual_size : Int32`, `max_size : Int32` | "Cookie size {n} bytes exceeds maximum..." |
| `SessionBindingException` | `Exception` | `binding_type : String` | "Session binding validation failed for {type}" |
| `InsecureSecretException` | `Exception` | -- | "Insecure session secret configuration" |
| `CircuitOpenException` | `Exception` | `time_until_retry : Time::Span` | "Circuit breaker is open. Retry in {n} seconds" |
| `ConnectionPoolTimeoutException` | `Exception` | -- | "Failed to acquire connection from pool..." |
| `ClusterException` | `Exception` | -- | "Cluster operation failed" |
| `ClusterConnectionException` | `ClusterException` | -- | "Cluster connection failed" |
| `ClusterSubscriptionException` | `ClusterException` | -- | "Cluster subscription failed" |

## Usage Pattern

```crystal
begin
  session = store[session_id]
rescue ex : Session::SessionExpiredException
  # Redirect to login
rescue ex : Session::SessionNotFoundException
  # Create new session
rescue ex : Session::StorageConnectionException
  # Degrade gracefully
end
```

## Exceptions with Extra Properties

```crystal
# CookieSizeExceededException
rescue ex : Session::CookieSizeExceededException
  ex.actual_size  # => 5120
  ex.max_size     # => 4096

# SessionBindingException
rescue ex : Session::SessionBindingException
  ex.binding_type  # => "ip" or "user_agent"

# CircuitOpenException
rescue ex : Session::CircuitOpenException
  ex.time_until_retry  # => 25.seconds
```

## Cause Chaining

All exceptions preserve the underlying cause:

```crystal
rescue ex : Session::SessionCorruptionException
  ex.message  # => "Session data is corrupted"
  ex.cause    # => JSON::ParseException (the original error)
end
```

## See Also

- [Error Handling](../resilience/error-handling.md) -- Graceful degradation patterns
- [Store API](store.md) -- Which operations raise which exceptions
