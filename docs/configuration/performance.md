# Performance Settings

Optimize session performance for your workload.

## Compression

Enable compression for large session data:

```crystal
Session.configure do |config|
  config.compress_data = true
  config.compression_threshold = 256  # Bytes
end
```

## Sliding Expiration

Extend session lifetime on each request:

```crystal
Session.configure do |config|
  config.sliding_expiration = true
  config.timeout = 30.minutes
end
```

## Retry Configuration

Configure retry behavior for transient failures:

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

## Circuit Breaker

Prevent cascading failures:

```crystal
Session.configure do |config|
  config.circuit_breaker_enabled = true
  config.circuit_breaker_config = Session::CircuitBreakerConfig.new(
    failure_threshold: 5,
    reset_timeout: 30.seconds,
    half_open_max_calls: 1
  )
end
```

## Clustering Performance

Optimize for multi-node deployments:

```crystal
Session.configure do |config|
  config.cluster.enabled = true
  config.cluster.local_cache_enabled = true
  config.cluster.local_cache_ttl = 1.minute
  config.cluster.local_cache_max_size = 100_000
end
```

## Performance Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `compress_data` | `Bool` | `false` | Enable compression |
| `compression_threshold` | `Int32` | `256` | Min bytes to compress |
| `sliding_expiration` | `Bool` | `false` | Extend on access |
| `enable_retry` | `Bool` | `true` | Enable retry logic |
| `circuit_breaker_enabled` | `Bool` | `false` | Enable circuit breaker |
