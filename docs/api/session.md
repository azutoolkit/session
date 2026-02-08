# Session API

`Session::Base` is the abstract class all session data types inherit from. It includes `JSON::Serializable` for automatic serialization.

## Defining a Session

```crystal
class UserSession < Session::Base
  property? authenticated : Bool = false
  property user_id : Int64? = nil
  property username : String? = nil
end
```

The `authenticated?` method is abstract and must be implemented by your subclass, either via `property?` or a custom method.

## Properties

| Property | Type | Default | Access | Description |
|----------|------|---------|--------|-------------|
| `session_id` | `String` | `UUID.random.to_s` | getter | Unique session identifier |
| `created_at` | `Time` | `Time.local` | getter | Creation timestamp |
| `expires_at` | `Time` | `timeout.from_now` | property | Expiration time |

## Abstract Methods

| Method | Return | Description |
|--------|--------|-------------|
| `authenticated?` | `Bool` | Must be implemented by subclass |

## Instance Methods

| Method | Return | Description |
|--------|--------|-------------|
| `expired?` | `Bool` | `true` if `Time.local > expires_at` |
| `valid?` | `Bool` | `true` if not expired |
| `touch` | `Nil` | Reset `expires_at` to `timeout.from_now` |
| `time_until_expiry` | `Time::Span` | Remaining time, or `Time::Span.zero` if expired |
| `==(other)` | `Bool` | Compare by `session_id` |

## Protected Methods

| Method | Return | Description |
|--------|--------|-------------|
| `reset_identity!` | `Nil` | Regenerate `session_id`, `created_at`, and `expires_at`. Used internally by `Store#regenerate_id` |

## Module-Level API

```crystal
# Configure the session library
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.store = Session::MemoryStore(UserSession).new
end

# Access configuration
Session.config                 # => Configuration instance
Session.config.store           # => Your configured store
Session.config.session         # => Store (raises if not configured)
Session.session                # => Shorthand for config.session
```

## See Also

- [Type-Safe Sessions](../features/type-safe-sessions.md) -- Defining session classes
- [Store API](store.md) -- Store method reference
