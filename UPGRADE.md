# Upgrade Guide

## Upgrading to 2.0

Version 2.0 introduces a simplified, class-based session architecture that replaces the `SessionData` module and `SessionId(T)` wrapper with a single `Session::Base` class. This is a breaking change that requires migration.

### Breaking Changes Summary

| Area | Old API | New API |
|------|---------|---------|
| Session definition | `struct` + `include Session::SessionData` | `class` + `< Session::Base` |
| Configuration | `config.provider = ...` | `config.store = ...` |
| Store creation | `.provider` suffix | `.new` directly |
| Data access | `session.data.property` | `session.property` |
| Global access | `Session.provider` | `Session.config.store` |
| Type wrappers | `SessionId(T)` | `T` directly |
| Callbacks | `Session::SessionData` param type | `Session::Base` param type |

---

### Step 1: Update Session Data Definitions

The `SessionData` module and struct-based sessions are replaced with class inheritance from `Session::Base`.

**Before:**

```crystal
struct UserSession
  include Session::SessionData

  property user_id : Int64?
  property username : String?
  property roles : Array(String) = [] of String

  def authenticated? : Bool
    !user_id.nil?
  end
end
```

**After:**

```crystal
class UserSession < Session::Base
  property? authenticated : Bool = false
  property user_id : Int64? = nil
  property username : String? = nil
  property roles : Array(String) = [] of String
end
```

Key differences:
- Use `class` instead of `struct`
- Inherit from `Session::Base` instead of including `Session::SessionData`
- `Session::Base` includes `JSON::Serializable` automatically
- `Session::Base` provides `session_id`, `created_at`, `expires_at`, `valid?`, `expired?`, `touch`, and `time_until_expiry`
- Must implement abstract method `authenticated?` (use `property?` for simple boolean)
- All properties must have default values (for parameterless constructor)

---

### Step 2: Update Configuration

The `provider` property is renamed to `store`, and store creation no longer uses the `.provider` suffix.

**Before:**

```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.provider = Session::MemoryStore(UserSession).provider
end
```

**After:**

```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.store = Session::MemoryStore(UserSession).new
end
```

Store creation changes for each backend:

```crystal
# Cookie Store
# Before: Session::CookieStore(UserSession).provider
# After:
config.store = Session::CookieStore(UserSession).new

# Memory Store
# Before: Session::MemoryStore(UserSession).provider
# After:
config.store = Session::MemoryStore(UserSession).new

# Redis Store
# Before: Session::RedisStore(UserSession).provider(client: Redis.new)
# After:
config.store = Session::RedisStore(UserSession).new(client: Redis.new)

# Clustered Redis Store (unchanged)
config.store = Session::ClusteredRedisStore(UserSession).new(client: Redis.new)

# Redis Store with connection pool
# Before: Session::RedisStore(UserSession).with_pool(config)
# After (unchanged):
config.store = Session::RedisStore(UserSession).with_pool(config)
```

---

### Step 3: Update Session Data Access

The `.data` accessor is removed. Session properties are accessed directly on the session object.

**Before:**

```crystal
session = store.create
session.data.user_id = 42
session.data.username = "alice"
puts session.data.authenticated?
```

**After:**

```crystal
session = store.create
session.user_id = 42
session.username = "alice"
puts session.authenticated?
```

For store-level access:

```crystal
# Before
provider.data.user_id
provider.data.username

# After
store.current_session.user_id
store.current_session.username
```

---

### Step 4: Update Global Store Access

**Before:**

```crystal
provider = Session.provider
session = provider.create
```

**After:**

```crystal
store = Session.config.store.not_nil!
session = store.create
```

---

### Step 5: Update Type Annotations

Remove `SessionId(T)` wrapper references — stores now work directly with `T`.

**Before:**

```crystal
def handle_session(session : Session::SessionId(UserSession))
  puts session.data.username
  puts session.session_id
end
```

**After:**

```crystal
def handle_session(session : UserSession)
  puts session.username
  puts session.session_id
end
```

---

### Step 6: Update Callbacks

Callback parameter types changed from `SessionData` to `Base`.

**Before:**

```crystal
config.on_started = ->(sid : String, data : Session::SessionData) do
  Log.info { "Session #{sid} started" }
end
```

**After:**

```crystal
config.on_started = ->(sid : String, session : Session::Base) do
  Log.info { "Session #{sid} started" }
end
```

---

### Step 7: Update HTTP Handler Initialization

**Before:**

```crystal
server = HTTP::Server.new([
  Session::SessionHandler.new(Session.provider),
  MyAppHandler.new,
])
```

**After:**

```crystal
store = Session.config.store.not_nil!

server = HTTP::Server.new([
  Session::SessionHandler.new(store),
  MyAppHandler.new,
])
```

---

### Step 8: Update Query Operations

**Before:**

```crystal
store.each_session { |s| puts s.data.username }
admins = store.find_by { |s| s.data.roles.includes?("admin") }
store.bulk_delete { |s| s.data.user_id == compromised_id }
```

**After:**

```crystal
store.each_session { |s| puts s.username }
admins = store.find_by { |s| s.roles.includes?("admin") }
store.bulk_delete { |s| s.user_id == compromised_id }
```

---

### Quick Migration Checklist

- [ ] Change `struct` session types to `class` inheriting from `Session::Base`
- [ ] Replace `include Session::SessionData` with `< Session::Base`
- [ ] Add default values to all session properties
- [ ] Rename `config.provider` to `config.store`
- [ ] Remove `.provider` suffix from store creation calls
- [ ] Replace all `.data.property` with `.property`
- [ ] Replace `Session.provider` with `Session.config.store.not_nil!`
- [ ] Update `SessionId(T)` type annotations to just `T`
- [ ] Update callback signatures from `SessionData` to `Base`
- [ ] Update HTTP handler initialization to use store directly
- [ ] Run `crystal spec` to verify all changes compile correctly
