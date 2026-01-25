# Basic Configuration

Configure Session to match your application's requirements.

## Minimal Configuration

```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.provider = Session::MemoryStore(UserSession).provider
end
```

## Full Configuration

```crystal
Session.configure do |config|
  # Core settings
  config.secret = ENV["SESSION_SECRET"]      # Required: encryption key
  config.timeout = 1.hour                     # Session lifetime
  config.session_key = "_session"             # Cookie name

  # Storage provider
  config.provider = Session::RedisStore(UserSession).provider(
    client: Redis.new
  )
end
```

## Configuration Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `secret` | `String` | (default) | Encryption secret (32+ chars recommended) |
| `timeout` | `Time::Span` | `1.hour` | Session lifetime |
| `session_key` | `String` | `"_session"` | Cookie name |
| `provider` | `Provider` | `nil` | Storage backend |

## Environment-Based Configuration

```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]

  case ENV["APP_ENV"]?
  when "production"
    config.timeout = 24.hours
    config.require_secure_secret = true
    config.provider = Session::RedisStore(UserSession).provider(
      client: Redis.new(url: ENV["REDIS_URL"])
    )
  when "test"
    config.timeout = 5.minutes
    config.provider = Session::MemoryStore(UserSession).provider
  else # development
    config.timeout = 1.hour
    config.provider = Session::MemoryStore(UserSession).provider
  end
end
```

## Accessing Configuration

```crystal
# Get current configuration
config = Session.config

puts config.timeout        # => 1.hour
puts config.session_key    # => "_session"

# Get configured provider
provider = Session.provider
```

## Related

- [Security Settings](security.md)
- [Performance Settings](performance.md)
