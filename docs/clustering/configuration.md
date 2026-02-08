# Cluster Configuration

This page covers all configuration options for session clustering.

## ClusterConfig Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `enabled` | `Bool` | `false` | Enable/disable clustering |
| `node_id` | `String` | Random UUID | Unique identifier for this node |
| `channel` | `String` | `"session:cluster:invalidate"` | Redis Pub/Sub channel name |
| `local_cache_enabled` | `Bool` | `true` | Enable local caching |
| `local_cache_ttl` | `Time::Span` | `30.seconds` | Cache entry time-to-live |
| `local_cache_max_size` | `Int32` | `10_000` | Maximum cache entries |
| `subscribe_timeout` | `Time::Span` | `5.seconds` | Pub/Sub subscription timeout |

## Basic Configuration

### Minimal Setup

```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]

  # Enable clustering with defaults
  config.cluster.enabled = true

  config.store = Session::ClusteredRedisStore(UserSession).new(
    client: Redis.new
  )
end
```

### Full Configuration

```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.timeout = 1.hour

  # Cluster configuration
  config.cluster.enabled = true
  config.cluster.node_id = ENV["NODE_ID"]? || "#{hostname}-#{process_id}"
  config.cluster.channel = "myapp:sessions:invalidate"
  config.cluster.local_cache_enabled = true
  config.cluster.local_cache_ttl = 1.minute
  config.cluster.local_cache_max_size = 50_000
  config.cluster.subscribe_timeout = 10.seconds

  config.store = Session::ClusteredRedisStore(UserSession).new(
    client: Redis.new(host: "redis.example.com", port: 6379)
  )
end
```

## Configuration Options Explained

### enabled

Controls whether clustering features are active.

```crystal
config.cluster.enabled = true  # Enable Pub/Sub and coordinator
config.cluster.enabled = false # Local cache only, no Pub/Sub
```

When disabled:
- Local caching still works (if `local_cache_enabled` is true)
- No Pub/Sub subscription is created
- No invalidation messages are broadcast

### node_id

A unique identifier for this application instance. Used to:
- Identify the source of invalidation messages
- Filter out self-generated messages (nodes ignore their own broadcasts)

```crystal
# Option 1: Environment variable
config.cluster.node_id = ENV["NODE_ID"]

# Option 2: Hostname + process ID
config.cluster.node_id = "#{System.hostname}-#{Process.pid}"

# Option 3: Random UUID (default)
config.cluster.node_id = UUID.random.to_s

# Option 4: Kubernetes pod name
config.cluster.node_id = ENV["POD_NAME"]? || UUID.random.to_s
```

### channel

The Redis Pub/Sub channel for invalidation messages.

```crystal
# Default channel
config.cluster.channel = "session:cluster:invalidate"

# Environment-specific channels
config.cluster.channel = "#{ENV["APP_ENV"]}:session:invalidate"

# Application-specific channels
config.cluster.channel = "myapp:session:invalidate"
```

Use different channels for:
- Different environments (staging vs production)
- Different applications sharing the same Redis instance
- Different session types within the same application

### local_cache_enabled

Controls whether sessions are cached locally in memory.

```crystal
config.cluster.local_cache_enabled = true  # Enable caching
config.cluster.local_cache_enabled = false # Always fetch from Redis
```

Disable local caching when:
- Memory is constrained
- Sessions change frequently
- You need real-time consistency

### local_cache_ttl

How long cached sessions remain valid before being evicted.

```crystal
config.cluster.local_cache_ttl = 30.seconds  # Default
config.cluster.local_cache_ttl = 1.minute    # Longer cache
config.cluster.local_cache_ttl = 5.seconds   # Near real-time
```

Considerations:
- Shorter TTL = more Redis reads, fresher data
- Longer TTL = fewer Redis reads, potentially stale data
- TTL should be shorter than your session timeout

### local_cache_max_size

Maximum number of sessions to keep in local cache.

```crystal
config.cluster.local_cache_max_size = 10_000  # Default
config.cluster.local_cache_max_size = 100_000 # High traffic apps
config.cluster.local_cache_max_size = 1_000   # Memory constrained
```

When the cache reaches max size:
1. Expired entries are removed first
2. If still full, LRU (least recently used) entries are evicted

Memory estimation:
- Each cached session uses approximately 1-5 KB depending on data size
- 10,000 sessions ~ 10-50 MB memory usage

## Passing Config to ClusteredRedisStore

You can pass configuration directly to the store:

```crystal
# Using global config
config.store = Session::ClusteredRedisStore(UserSession).new(
  client: Redis.new
)  # Uses Session.config.cluster

# Using custom config
custom_config = Session::ClusterConfig.new(
  enabled: true,
  node_id: "custom-node",
  local_cache_ttl: 1.minute
)

config.store = Session::ClusteredRedisStore(UserSession).new(
  client: Redis.new,
  config: custom_config
)
```

## Environment-Based Configuration

```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]

  case ENV["APP_ENV"]?
  when "production"
    config.cluster.enabled = true
    config.cluster.local_cache_ttl = 1.minute
    config.cluster.local_cache_max_size = 100_000
  when "staging"
    config.cluster.enabled = true
    config.cluster.local_cache_ttl = 30.seconds
    config.cluster.local_cache_max_size = 10_000
  else # development
    config.cluster.enabled = false
    config.cluster.local_cache_enabled = true
    config.cluster.local_cache_ttl = 10.seconds
  end

  redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379"
  config.store = Session::ClusteredRedisStore(UserSession).new(
    client: Redis.new(url: redis_url)
  )
end
```

## Combining with Other Features

### With Circuit Breaker

```crystal
Session.configure do |config|
  config.cluster.enabled = true
  config.circuit_breaker_enabled = true
  config.circuit_breaker_config = Session::CircuitBreakerConfig.new(
    failure_threshold: 5,
    reset_timeout: 30.seconds
  )

  config.store = Session::ClusteredRedisStore(UserSession).new(
    client: Redis.new
  )
end
```

### With Encryption

```crystal
Session.configure do |config|
  config.cluster.enabled = true
  config.encrypt_redis_data = true  # Encrypt data at rest in Redis

  config.store = Session::ClusteredRedisStore(UserSession).new(
    client: Redis.new
  )
end
```

### With Compression

```crystal
Session.configure do |config|
  config.cluster.enabled = true
  config.compress_data = true
  config.compression_threshold = 512

  config.store = Session::ClusteredRedisStore(UserSession).new(
    client: Redis.new
  )
end
```
