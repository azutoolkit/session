# Metrics

Session provides a pluggable metrics backend for observability. Track session creation rates, load times, error counts, and more.

## Configuration

```crystal
Session.configure do |config|
  config.metrics_backend = Session::Metrics::LogBackend.new
end
```

## Built-in Backends

| Backend | Behavior |
|---------|----------|
| `NullBackend` | Discards all metrics (default) |
| `LogBackend` | Logs metrics via `Session::Log` at info level |

## Backend Interface

Implement `Metrics::Backend` to integrate with your metrics system (StatsD, Prometheus, Datadog, etc.):

```crystal
class StatsDBackend < Session::Metrics::Backend
  def increment(name : String, tags : Hash(String, String) = {} of String => String) : Nil
    # Send counter to StatsD
  end

  def timing(name : String, duration : Time::Span, tags : Hash(String, String) = {} of String => String) : Nil
    # Send timing to StatsD
  end

  def gauge(name : String, value : Float64, tags : Hash(String, String) = {} of String => String) : Nil
    # Send gauge to StatsD
  end
end
```

## Available Metrics

| Constant | Type | Description |
|----------|------|-------------|
| `session.created` | Counter | Session created |
| `session.loaded` | Counter | Session loaded from request |
| `session.deleted` | Counter | Session deleted |
| `session.regenerated` | Counter | Session ID regenerated |
| `session.expired` | Counter | Session expired |
| `session.error` | Counter | Session error (tagged with `error` type) |
| `session.load_time` | Timing | Time to load a session |
| `session.store_time` | Timing | Time to store a session |
| `session.active_count` | Gauge | Number of active sessions |
| `session.circuit_breaker.open` | Counter | Circuit breaker opened |
| `session.circuit_breaker.half_open` | Counter | Circuit breaker entered half-open |
| `session.retry.attempt` | Counter | Retry attempt made |

All metrics are tagged with `store` (the store type name). Error metrics also include an `error` tag with the exception class name.

## Helper Methods

The `Metrics::Helper` module provides convenience methods:

```crystal
Session::Metrics::Helper.record_created("redis")
Session::Metrics::Helper.record_load_time("redis", duration)
Session::Metrics::Helper.record_error("redis", "ConnectionError")
Session::Metrics::Helper.record_active_count("redis", store.size)

# Time an operation and record metrics automatically
Session::Metrics::Helper.time_operation("redis", "load") do
  store[session_id]
end
```

## See Also

- [Query Interface](query-interface.md)
- [Circuit Breaker](../resilience/circuit-breaker.md)
