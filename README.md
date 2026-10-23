# Session

**Type-safe, production-ready session management for Crystal.**

[![Crystal CI](https://github.com/azutoolkit/session/workflows/Crystal%20CI/badge.svg?branch=master)](https://github.com/azutoolkit/session/actions)
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/9a663614a1844a188270ba015cd14651)](https://app.codacy.com/gh/azutoolkit/session)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Why Session?

| | |
|---|---|
| **Type-Safe** | Define sessions as Crystal classes with compile-time guarantees |
| **Multiple Backends** | Cookie, Memory, Redis, or Clustered Redis—pick what fits |
| **Battle-Tested Security** | AES-256 encryption, HMAC-SHA256, PBKDF2, client binding |
| **Production Resilience** | Circuit breakers, retry logic, graceful degradation |
| **Azu Ready** | `require "session/azu"` adds typed `context.session` and `context.flash` |

---

## Quick Start

**Install** (add to `shard.yml`):

```yaml
dependencies:
  session:
    github: azutoolkit/session
```

**Use** (< 30 seconds to your first session):

```crystal
require "session"

# Define your session data
class UserSession < Session::Base
  property? authenticated : Bool = false
  property username : String? = nil
end

# Declare the session type and its store once (this is what types `config.store`)
Session.use_store(Session::MemoryStore(UserSession))

# Configure once
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.store = Session::MemoryStore(UserSession).new
end

# Create and use sessions
store = Session.config.store.not_nil!
session = store.create
session.username = "alice"
```

That's it. You're ready to build.

---

## Key Features

### Storage Backends

| Backend | Best For | Persistence | Multi-Node |
|---------|----------|-------------|------------|
| **CookieStore** | Stateless apps, serverless | Client-side | Yes |
| **MemoryStore** | Development, single-server | None | No |
| **RedisStore** | Production deployments | Redis | Yes |
| **ClusteredRedisStore** | High-scale, multi-node | Redis + local cache | Yes |

<!-- skip -->
```crystal
# One store at a time: `Session.use_store(StoreType)` declares which
# Cookie (stateless, client-side)
config.store = Session::CookieStore(UserSession).new

# Memory (development)
config.store = Session::MemoryStore(UserSession).new

# Redis (production)
config.store = Session::RedisStore(UserSession).new(client: Redis.new)

# Clustered Redis (high-scale production)
config.cluster.enabled = true
config.store = Session::ClusteredRedisStore(UserSession).new(client: Redis.new)
```

### Security

- **Encryption** — AES-256-CBC with random IV per operation
- **Signing** — HMAC-SHA256 to detect tampering
- **Key Derivation** — Optional PBKDF2 with configurable iterations
- **Client Binding** — Lock sessions to IP and/or User-Agent
- **Size Protection** — Automatic cookie size validation (4KB limit)

```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]       # 32+ chars recommended
  config.use_kdf = true                       # Enable PBKDF2
  config.kdf_iterations = 100_000             # OWASP recommended
  config.bind_to_ip = true                    # Prevent session hijacking
  config.bind_to_user_agent = true
end
```

### Resilience

- **Circuit Breaker** — Fail fast when backends are down
- **Retry Logic** — Exponential backoff with jitter
- **Compression** — Gzip for large session payloads

```crystal
Session.configure do |config|
  config.circuit_breaker_enabled = true
  config.circuit_breaker_config = Session::CircuitBreakerConfig.new(
    failure_threshold: 5,
    reset_timeout: 30.seconds
  )

  config.enable_retry = true
  config.retry_config = Session::RetryConfig.new(
    max_attempts: 3,
    base_delay: 100.milliseconds,
    backoff_multiplier: 2.0
  )
end
```

### Clustering

Multi-node session management with Redis Pub/Sub invalidation and local caching.

```mermaid
flowchart LR
    subgraph Node_A["Node A"]
        A_Cache["Local Cache"]
    end
    subgraph Node_B["Node B"]
        B_Cache["Local Cache"]
    end
    Redis[("Redis")]
    PubSub{{"Pub/Sub"}}

    A_Cache <--> Redis
    B_Cache <--> Redis
    A_Cache -.->|invalidate| PubSub -.->|evict| B_Cache
```

```crystal
Session.configure do |config|
  config.cluster.enabled = true
  config.cluster.node_id = ENV["POD_NAME"]? || UUID.random.to_s
  config.cluster.local_cache_ttl = 30.seconds
  config.cluster.local_cache_max_size = 10_000

  config.store = Session::ClusteredRedisStore(UserSession).new(
    client: Redis.new(url: ENV["REDIS_URL"])
  )
end
```

---

## API Essentials

### Store Operations

```crystal
store = Session.config.store.not_nil!

store.create              # New session
store.delete              # Destroy session
store.regenerate_id       # New ID, keep data (post-login security)
store.valid?              # Check validity
store.current_session     # Access your typed session data
store.flash               # One-request flash messages
```

### Session Object

```crystal
session = store.current_session

session.session_id           # Unique ID
session.username             # Your session properties directly
session.valid?               # Not expired?
session.expired?             # Past expiration?
session.time_until_expiry    # Remaining lifetime
session.touch                # Extend expiration
```

### Flash Messages

```crystal
# Set (available next request)
store.flash["notice"] = "Saved successfully"
store.flash["error"] = "Something went wrong"

# Read (on the next request only; the request after that no longer sees it)
store.flash.now["notice"]  # => "Saved successfully"
```

### Query & Bulk Operations

```crystal
store = Session::MemoryStore(UserSession).new
compromised_id = 42_i64

# Iterate sessions
store.each_session { |s| puts s.username }

# Find by criteria
admins = store.find_by { |s| s.roles.includes?("admin") }

# Bulk delete (e.g., revoke compromised user)
store.bulk_delete { |s| s.user_id == compromised_id }
```

---

## HTTP Integration

```crystal
require "http/server"

class HelloHandler
  include HTTP::Handler

  def call(context : HTTP::Server::Context)
    context.response.print "Hello, #{Session.session.current_session.username || "guest"}"
  end
end

Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.store = Session::MemoryStore(UserSession).new
end

server = HTTP::Server.new([
  Session::SessionHandler.new(Session.session),
  HelloHandler.new,
] of HTTP::Handler)

server.listen(8080)
```

`Session::SessionHandler` loads the session from the request cookies, validates client binding, recovers from corrupt or expired sessions with a fresh one, and sends the cookies with the response, even for large or streamed bodies. `Session.session` is the store you configured, typed (`Session.use_store`).

## Azu Integration

`require "session/azu"` is opt-in. It adds the typed `context.session` and `context.flash` to `HTTP::Server::Context`, which is what an Azu endpoint has at hand.

```crystal
require "session/azu"

class UserSession < Session::Base
  property user_id : Int64? = nil

  def authenticated? : Bool
    !user_id.nil?
  end
end

Session::Web.use_store(Session::CookieStore(UserSession))

Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.store = Session::CookieStore(UserSession).new
end

def sign_in(context : HTTP::Server::Context, user_id : Int64) : Nil
  Session.session.authenticate { |session| session.user_id = user_id }
  context.flash["notice"] = "Welcome back"
end

def welcome(context : HTTP::Server::Context) : String?
  context.flash.now["notice"]?
end
```

Cookies are always `HttpOnly`, `Secure` and `SameSite=Strict`; `config.cookie_secure` and `config.cookie_same_site` change that. See the [Azu guide](docs/integrations/azu-framework.md).

---

## Configuration Reference

```crystal
Session.configure do |config|
  # Core
  config.secret = ENV["SESSION_SECRET"]   # Required
  config.timeout = 1.hour                 # Session lifetime
  config.session_key = "_session"         # Cookie name
  config.sliding_expiration = true        # Extend on access

  # Security
  config.use_kdf = true                   # PBKDF2 key derivation
  config.kdf_iterations = 100_000
  config.bind_to_ip = true
  config.bind_to_user_agent = true
  config.encrypt_redis_data = true

  # Performance
  config.compress_data = true
  config.compression_threshold = 256

  # Resilience
  config.enable_retry = true
  config.circuit_breaker_enabled = true

  # Clustering
  config.cluster.enabled = true
  config.cluster.local_cache_ttl = 30.seconds
  config.cluster.local_cache_max_size = 10_000

  # Callbacks
  config.on_started = ->(id : String, session : Session::Base) { Log.info { "Session #{id} created" } }
  config.on_deleted = ->(id : String, session : Session::Base) { Log.info { "Session #{id} destroyed" } }

  # Metrics
  config.metrics_backend = Session::Metrics::LogBackend.new
end
```

---

## Documentation

Full documentation available at [GitBook](https://azutoolkit.gitbook.io/session) (or see the `docs/` directory).

- [Getting Started](docs/getting-started/quick-start.md)
- [Configuration Guide](docs/configuration/basic.md)
- [Storage Backends](docs/storage-backends/overview.md)
- [Clustering Guide](docs/clustering/overview.md)
- [Security Best Practices](docs/configuration/security.md)
- [AZU Framework Integration](docs/integrations/azu-framework.md)
- [HTTP::Server Integration](docs/integrations/http-server.md)
- [Upgrade Guide](UPGRADE.md)

---

## Contributing

1. Fork it
2. Create your branch (`git checkout -b feature/awesome`)
3. Write tests
4. Make sure `crystal spec` passes
5. Commit and push
6. Open a PR

---

## License

MIT — see [LICENSE](LICENSE)

---

Built with Crystal. Maintained by [@eliasjpr](https://github.com/eliasjpr).
