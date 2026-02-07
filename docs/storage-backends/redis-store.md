# Redis Store

The Redis Store provides persistent, distributed session storage.

## Overview

```mermaid
flowchart LR
    App["Application"] --> Redis[("Redis Server")]
    Redis --> App
```

## Usage

### Direct Client

```crystal
Session.configure do |config|
  config.provider = Session::RedisStore(UserSession).new(
    client: Redis.new(host: "localhost", port: 6379)
  )
end
```

### Connection Pool (Recommended for Production)

RedisStore now supports connection pooling for better resource management:

```crystal
Session.configure do |config|
  # Using factory method
  pool_config = Session::ConnectionPoolConfig.new(
    size: 20,
    timeout: 2.seconds
  )
  config.provider = Session::RedisStore(UserSession).with_pool(pool_config)
end
```

Or with an existing pool:

```crystal
pool = Session::ConnectionPool.new(config)
config.provider = Session::RedisStore(UserSession).new(pool: pool)
```

**Note:** `PooledRedisStore` is deprecated. Use `RedisStore.with_pool()` instead.

See [Phase 3: Store Consolidation](../architecture/phase-3-store-consolidation.md) for migration details.

## Characteristics

| Feature | Value |
|---------|-------|
| Storage | Redis server |
| Max Size | Redis memory |
| Persistence | Redis persistence |
| Multi-node | Yes |
| TTL | Automatic |

## Best For

- Production deployments
- Multi-server architectures
- Session persistence required

## With Encryption

```crystal
Session.configure do |config|
  config.encrypt_redis_data = true
  config.provider = Session::RedisStore(UserSession).provider(
    client: Redis.new
  )
end
```

## With Circuit Breaker

```crystal
Session.configure do |config|
  config.circuit_breaker_enabled = true
  config.provider = Session::RedisStore(UserSession).provider(
    client: Redis.new
  )
end
```

## Health Check

```crystal
store = Session::RedisStore(UserSession).new(client: Redis.new)
puts store.healthy?  # => true/false
```

## For High Traffic

Consider the [Clustered Redis Store](clustered-redis-store.md) for local caching and reduced Redis load.
