# Type-Safe Sessions

Define your session data as a Crystal class with compile-time type safety. All session types inherit from `Session::Base` and are parameterized through the generic store system.

## Defining a Session

```crystal
class UserSession < Session::Base
  property? authenticated : Bool = false
  property user_id : Int64? = nil
  property username : String? = nil
  property role : String = "guest"
end
```

The `authenticated?` method is abstract in `Session::Base` and must be implemented. Using `property?` is the simplest approach, but you can also define it manually:

```crystal
class UserSession < Session::Base
  property user_id : Int64? = nil

  def authenticated? : Bool
    !user_id.nil?
  end
end
```

## Built-in Properties

Every session inherits these properties from `Session::Base`:

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `session_id` | `String` | `UUID.random.to_s` | Unique identifier (getter only) |
| `created_at` | `Time` | `Time.local` | Creation timestamp (getter only) |
| `expires_at` | `Time` | `timeout.from_now` | Expiration time (getter/setter) |

## Built-in Methods

| Method | Return | Description |
|--------|--------|-------------|
| `expired?` | `Bool` | True if past expiration time |
| `valid?` | `Bool` | True if not expired |
| `touch` | `Nil` | Reset expiration to `timeout.from_now` |
| `time_until_expiry` | `Time::Span` | Remaining lifetime (zero if expired) |

## JSON Serialization

`Session::Base` includes `JSON::Serializable`. All properties you add must be JSON-serializable:

```crystal
class UserSession < Session::Base
  property? authenticated : Bool = false
  property roles : Array(String) = [] of String   # OK - Array(String) is serializable
  property last_login : Time? = nil                # OK - Time is serializable
end
```

## Generic Type System

Stores are parameterized with your session type, providing compile-time safety:

```crystal
# The type parameter ensures only UserSession instances are stored
store = Session::MemoryStore(UserSession).new

session = store.create          # Returns UserSession, not Session::Base
session.username = "alice"      # Compile-time checked
session.role                    # => "guest"
```

This means you cannot accidentally store the wrong session type or access properties that don't exist.

## See Also

- [Session Lifecycle](session-lifecycle.md) -- Create, load, and manage sessions
- [Quick Start](../getting-started/quick-start.md)
