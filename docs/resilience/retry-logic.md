# Retry Logic

Automatic retry with exponential backoff and jitter for transient failures like network timeouts and connection drops.

## Configuration

```crystal
Session.configure do |config|
  config.enable_retry = true
  config.retry_config = Session::RetryConfig.new(
    max_attempts: 3,
    base_delay: 100.milliseconds,
    max_delay: 5.seconds,
    backoff_multiplier: 2.0,
    jitter: 0.1
  )
end
```

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `max_attempts` | `Int32` | `3` | Total attempts (including first) |
| `base_delay` | `Time::Span` | `100.milliseconds` | Initial delay between retries |
| `max_delay` | `Time::Span` | `5.seconds` | Maximum delay cap |
| `backoff_multiplier` | `Float64` | `2.0` | Delay multiplier per attempt |
| `jitter` | `Float64` | `0.1` | Random variation (0.1 = +/-10%) |

## How Backoff Works

Delay formula: `base_delay * (backoff_multiplier ^ attempt) * jitter_factor`, capped at `max_delay`.

With defaults, approximate delays:
- Attempt 1 fails: ~100ms wait
- Attempt 2 fails: ~200ms wait
- Attempt 3: final attempt, no retry

Jitter adds random variation to prevent multiple clients from retrying in lockstep (thundering herd).

## Store Integration

When `enable_retry` is true, `RedisStore` automatically wraps all operations with retry logic using the `retryable_connection_error?` predicate. No manual retry code is needed.

## Direct Usage

For custom retry logic outside the store:

```crystal
# Retry any exception
Session::Retry.with_retry(Session.config.retry_config) do
  some_operation
end

# Retry only specific exceptions
Session::Retry.with_retry_if(
  ->(ex : Exception) { Session::Retry.retryable_connection_error?(ex) },
  Session.config.retry_config
) do
  some_operation
end
```

## Retry Predicates

| Predicate | Retries On |
|-----------|------------|
| `retryable_connection_error?` | `IO::Error`, `Redis::ConnectionError`, `Redis::CommandTimeoutError` |
| `retryable_timeout_error?` | `IO::TimeoutError`, `Redis::CommandTimeoutError` |
| `retryable_network_error?` | `IO::Error`, `Redis::ConnectionError`, `Redis::CommandTimeoutError` |

## See Also

- [Circuit Breaker](circuit-breaker.md)
- [Error Handling](error-handling.md)
