# Installation

## Requirements

- Crystal 1.0.0 or higher
- Redis 5.0+ (for Redis and Clustered Redis stores)

## Add Dependency

Add the session shard to your `shard.yml`:

```yaml
dependencies:
  session:
    github: azutoolkit/session
    version: ~> 1.0
```

## Install

Run shards to install the dependency:

```bash
shards install
```

## Verify Installation

Create a test file to verify the installation:

```crystal
# test_session.cr
require "session"

class TestSession < Session::Base
  property test : String = "Hello"
end

Session.configure do |config|
  config.secret = "test-secret-for-verification"
  config.store = Session::MemoryStore(TestSession).new
end

store = Session.config.store.not_nil!
session = store.create
puts "Session ID: #{session.session_id}"
puts "Installation successful!"
```

Run the test:

```bash
crystal run test_session.cr
```

## Optional Dependencies

### Redis Support

For Redis-based stores, ensure you have Redis installed and running:

```bash
# macOS
brew install redis
brew services start redis

# Ubuntu/Debian
sudo apt-get install redis-server
sudo systemctl start redis

# Docker
docker run -d -p 6379:6379 redis:7-alpine
```

Verify Redis connection:

```bash
redis-cli ping
# Should return: PONG
```

## Next Steps

- [Quick Start](quick-start.md) - Create your first session
- [Configuration](../configuration/basic.md) - Configure session options
