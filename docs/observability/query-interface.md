# Query Interface

`QueryableStore(T)` provides methods to search, filter, and bulk-operate on sessions. This is useful for admin dashboards, session management, and security operations like revoking compromised sessions.

## Supported Stores

| Store | QueryableStore |
|-------|---------------|
| MemoryStore | Yes |
| RedisStore | Yes |
| CookieStore | No (stateless) |
| ClusteredRedisStore | Yes (delegates to RedisStore) |

## Methods

| Method | Return | Description |
|--------|--------|-------------|
| `each_session(&block : T -> Nil)` | `Nil` | Iterate all valid sessions |
| `find_by(&predicate : T -> Bool)` | `Array(T)` | Find sessions matching a condition |
| `find_first(&predicate : T -> Bool)` | `T?` | Find first matching session |
| `count_by(&predicate : T -> Bool)` | `Int64` | Count matching sessions |
| `bulk_delete(&predicate : T -> Bool)` | `Int64` | Delete matching sessions, returns count |
| `all_session_ids` | `Array(String)` | List all valid session IDs |

## Examples

```crystal
store = Session::MemoryStore(UserSession).new

# Find all admin sessions
admins = store.find_by { |s| s.role == "admin" }

# Count authenticated sessions
count = store.count_by { |s| s.authenticated? }

# Revoke all sessions for a compromised user
deleted = store.bulk_delete { |s| s.user_id == compromised_id }

# Find first matching session
session = store.find_first { |s| s.username == "alice" }

# Get all session IDs
ids = store.all_session_ids

# Iterate all sessions
store.each_session { |s| puts "#{s.session_id}: #{s.username}" }
```

## Performance Notes

- **MemoryStore** iterates over an in-memory `Hash` -- fast for small to medium session counts
- **RedisStore** uses `SCAN` (not `KEYS`) for safe iteration that doesn't block the Redis server. Bulk deletes are batched in groups of 100
- **ClusteredRedisStore** delegates query operations to the underlying RedisStore, bypassing the local cache

## See Also

- [Store API](../api/store.md) -- Full store method reference
- [Metrics](metrics.md)
