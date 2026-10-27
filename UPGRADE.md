# Upgrade Guide

## Releases

There is no changelog; this list says what a release contains, and the sections below say what to change.

**1.1.0** (tag `v1.1`: the release job drops a `.0` patch), the first release from `master` after 1.0.31. The
`v1.0.32` tag is not on `master`: it was cut from the merge ref of pull request #2 before the release job ran on
pushes only, so it holds that pull request's change and nothing after it.

- Opt-in Azu integration: `require "session/azu"` and `Session::Web.use_store` (typed `context.session` and
  `context.flash`), `config.cookie_secure` and `config.cookie_same_site`, and the session is saved before the first
  byte of the response is written.
- Expired sessions are refused when loaded, for every store; `RedisStore` sessions end at `expires_at` unless
  `sliding_expiration` is on.
- No published default secret: the secret comes from `SESSION_SECRET` (random per process without it, outside
  production and staging); production and staging refuse a missing or published secret, a secret shorter than
  32 bytes is refused, and `Session.configure` checks it at boot when the store encrypts with it. A `MemoryStore` never
  needs it.
- Isolation fixes: the current session, the flash messages and `CookieStore`'s request cookies are kept per request,
  not per store. `bind_to_ip` and `bind_to_user_agent` now answer a session used from another client with a
  fresh session (they never refused anything), with `trust_proxy_headers` for `X-Forwarded-For`; `Store#authenticate` changes privileges under
  a new session id.
- Crystal 1.22.1 or newer.

## No published default secret

The secret used to default to a string published in this repository, so an app that never set one signed its
cookies with a key anyone could use to forge a session. Now:

- `config.secret` defaults to `SESSION_SECRET`. Without it, a random key for this process (one warning), so
  sessions end when the process restarts and are not shared between instances. Set `SESSION_SECRET` to keep them.
- In production and staging a missing secret raises `Session::InsecureSecretException` wherever the secret is
  used. With a `CookieStore`, or a Redis store with `encrypt_redis_data`, `Session::SessionHandler` then fails every
  request with `Session::InsecureSecretException` (a 500, logged by the server) instead of answering without a
  working session; a store that does not encrypt never reads the secret, so nothing is raised. A `MemoryStore`
  never encrypts, also under the `:production`, `:high_security` and `:clustered` presets, which turn
  `encrypt_redis_data` on.
- A secret shorter than 32 bytes raises `Session::InsecureSecretException` too, instead of an `ArgumentError` from
  AES that the handler logged and swallowed. This holds with `use_kdf` on (the `:production`, `:high_security` and
  `:clustered` presets): the HMAC signature uses the secret itself, so PBKDF2 does not make a short one safe.
- `Session.configure` checks the secret when the configured store encrypts with it (a `CookieStore`, or a Redis
  store with `encrypt_redis_data`), so a missing or short secret fails at boot instead of on every request. Set the
  secret (or `SESSION_SECRET`) before, or inside, the `Session.configure` block that sets such a store.
- For store authors: `Session::Store#encrypts_with_secret?` tells `Session.configure` and `Session::SessionHandler`
  whether the store needs the secret. The default follows `encrypt_redis_data`; `MemoryStore` returns `false` and
  `CookieStore` `true`. A custom store that encrypts with `Session.config.encryptor` regardless of
  `encrypt_redis_data` should override it to return `true`, and one that never encrypts should return `false`.
- `require_secure_secret` now reads `CRYSTAL_ENV` (case-insensitive) when it is checked, not when the shard loads;
  setting it explicitly still wins.
- `config.secret = nil` goes back to the default. `Configuration::DEFAULT_SECRET` still exists and is still refused
  where `require_secure_secret` holds.

## Expired sessions are refused when loaded (behavior change)

No API change, but sessions can now end sooner than before. Semver impact: patch (security fix).

- Every store now refuses a session whose `expires_at` has passed when it is loaded, and the request starts a fresh
  session. A copied `CookieStore` cookie no longer stays signed in after the timeout.
- `RedisStore` sessions now end at their `expires_at` even for a visitor who keeps using them, when
  `sliding_expiration` is `false` (the default): `expires_at` is set when the session is created (or regenerated),
  so the session lasts `timeout` from then. Before, every save ran `SETEX`, which reset the Redis TTL, and nothing
  read `expires_at`, so an active session lived indefinitely. To keep sessions alive while they are used, set
  `config.sliding_expiration = true`: each request then moves `expires_at` to `timeout` from now. The
  `:development`, `:production`, `:high_security` and `:clustered` presets already set it, so an app that applies
  one of them keeps sliding sessions.
- A stored or signed payload without `expires_at` no longer loads. Payloads written by released versions always
  carry it. A `Session::Base` subclass that overrides `after_initialize` must call `super`.

## Crystal 1.22.1 or newer (no code change)

`shard.yml` now declares `crystal: ">= 1.22.1"`. It was `crystal: 1.4.1`, a 1.4.1 minimum that no CI job ever built.
`.tool-versions` and CI now use 1.22.1 (the oldest supported version; CI also runs the latest release). On an older
Crystal, `shards` only prints a "may be incompatible with Crystal" warning and still installs, but the specs run on
1.22.1 and newer only, so older compilers are unsupported: upgrade the compiler.

## Azu integration, cookie options and the response commit (no breaking change)

Nothing here needs a code change. Semver impact: minor (new opt-in API, one bug fix).

- `require "session/azu"` is new and opt-in: `Session::Web.use_store(Session::CookieStore(UserSession))` declares the store like `Session.use_store` does, and adds the typed `context.session` and `context.flash` to `HTTP::Server::Context`. See [the Azu guide](docs/integrations/azu-framework.md).
- `config.cookie_secure` (default `true`) and `config.cookie_same_site` (default `SameSite::Strict`) replace the values that were hard-coded; the defaults are the previous behavior.
- `Session::SessionHandler` now saves the session just before the first byte of the response is written. Before, a response larger than the output buffer, or one that was flushed, went out without its `Set-Cookie`: a new session was never established and a changed cookie-store session was lost. The handler wraps `context.response.output` to do this; a handler placed after it may wrap the output again.
- `config.allow_insecure_cookies` and `Session::InvalidCookieOptions`: `Session.configure` now refuses `cookie_same_site = None` with `cookie_secure = false`, and `cookie_secure = false` when `require_secure_secret` is on, unless `allow_insecure_cookies = true`. Only code that already turned `Secure` off is affected.
- `Session::Store#current_session?` returns the request's session without creating one.
- `Session::Flash#to_h` returns the messages a view shows.

## Upgrading from the `SessionData` API to `Session::Base`

Releases before v1.0.28 defined sessions with the `SessionData` module and the `SessionId(T)` wrapper. From v1.0.28 on, a single `Session::Base` class replaces both. There was no 2.0 release: this migration happens inside the 1.0.x line, and the "Before" snippets below show code that no longer compiles.

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

<!-- skip -->
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
- `authenticated?` returns `false` unless you override it (or declare `property? authenticated`)
- All properties must have default values (for parameterless constructor)

---

### Step 2: Update Configuration

The `provider` property is renamed to `store`, and store creation no longer uses the `.provider` suffix.

**Before:**

<!-- skip -->
```crystal
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.provider = Session::MemoryStore(UserSession).provider
end
```

**After:**

```crystal
Session.use_store(Session::MemoryStore(UserSession))

Session.configure do |config|
  # The secret is read from SESSION_SECRET (random per process in development without it)
  config.store = Session::MemoryStore(UserSession).new
end
```

`Session.use_store` declares the store type once, before `Session.configure`; it is what types `config.store` and `Session.session`.

Store creation changes for each backend (one store at a time, the one `Session.use_store` names):

<!-- skip -->
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

<!-- skip -->
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

<!-- skip -->
```crystal
# Before
provider.data.user_id
provider.data.username
```

```crystal
# After
store.current_session.user_id
store.current_session.username
```

---

### Step 4: Update Global Store Access

**Before:**

<!-- skip -->
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

<!-- skip -->
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

<!-- skip -->
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

<!-- skip -->
```crystal
server = HTTP::Server.new([
  Session::SessionHandler.new(Session.provider),
  MyAppHandler.new,
])
```

**After:**

```crystal
class MyAppHandler
  include HTTP::Handler

  def call(context : HTTP::Server::Context)
    context.response.print "ok"
  end
end

server = HTTP::Server.new([
  Session::SessionHandler.new(Session.session),
  MyAppHandler.new,
] of HTTP::Handler)
```

---

### Step 8: Update Query Operations

**Before:**

<!-- skip -->
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
