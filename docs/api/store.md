# Store API

`Store(T)` is the abstract base class for all storage backends. `T` must inherit from `Session::Base` and provide a parameterless constructor.

## Abstract Methods

Subclasses must implement:

| Method | Signature | Description |
|--------|-----------|-------------|
| `storage` | `: String` | Backend name (e.g., `"memory"`, `"redis"`) |
| `current_session` | `: T` | Get current session |
| `current_session=` | `(T)` | Set current session |
| `[]` | `(key : String) : T` | Fetch session by ID (raises `SessionNotFoundException`) |
| `[]?` | `(key : String) : T?` | Fetch session by ID (returns `nil`) |
| `[]=` | `(key : String, session : T) : T` | Store a session |
| `delete` | `(key : String)` | Delete session by ID |
| `size` | `: Int64` | Count stored sessions |
| `clear` | | Remove all sessions |

## Lifecycle Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `create` | `: T` | Create and store a new session. Triggers `:started` |
| `delete` | (no args) | Delete current session, create fresh one. Triggers `:deleted` |
| `regenerate_id` | `: T` | New ID, preserve data. Triggers `on_regenerated` |
| `load_from` | `(HTTP::Cookies) : T?` | Load session from request cookies. Triggers `:loaded` |
| `set_cookies` | `(HTTP::Cookies, String) : Nil` | Set session cookie on response. Triggers `:client` |

## Utility Methods

| Method | Return | Description |
|--------|--------|-------------|
| `session_id` | `String` | Current session's ID |
| `valid?` | `Bool` | Current session not expired? |
| `flash` | `Flash` | Flash message store |
| `timeout` | `Time::Span` | Configured session timeout |
| `session_key` | `String` | Cookie name (default `"_session"`) |
| `create_session_cookie` | `HTTP::Cookie` | Build a session cookie for a host |

## Callbacks

`on(event, session_id, session)` dispatches to configured callbacks:

| Event | Callback Property | Signature |
|-------|-------------------|-----------|
| `:started` | `on_started` | `(String, Session::Base) -> Nil` |
| `:loaded` | `on_loaded` | `(String, Session::Base) -> Nil` |
| `:client` | `on_client` | `(String, Session::Base) -> Nil` |
| `:deleted` | `on_deleted` | `(String, Session::Base) -> Nil` |

`regenerate_id` triggers `on_regenerated` directly with signature `(String, String, Session::Base) -> Nil` (old_id, new_id, session).

## Concrete Implementations

- [MemoryStore](../storage-backends/memory-store.md) -- In-memory, includes `QueryableStore`
- [RedisStore](../storage-backends/redis-store.md) -- Redis backend, includes `QueryableStore`
- [CookieStore](../storage-backends/cookie-store.md) -- Client-side encrypted cookies
- [ClusteredRedisStore](../storage-backends/clustered-redis-store.md) -- Redis + local cache + Pub/Sub

## See Also

- [Session API](session.md) -- `Session::Base` class reference
- [Query Interface](../observability/query-interface.md) -- `QueryableStore(T)` methods
