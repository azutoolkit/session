# Flash Messages

Flash provides temporary message storage that persists for exactly one request, then auto-clears. Useful for notifications like "Saved successfully" or "Invalid credentials".

## How It Works

Flash uses two internal hashes:

- **`next`** -- Messages set during the current request, available in the next request
- **`now`** -- Messages from the previous request, available for reading in the current request

At the start of each request, `rotate!` moves `next` into `now` and clears `next`. This happens automatically when `Store#load_from` is called.

## Basic Usage

```crystal
# Set a message (available next request)
store.flash["notice"] = "Saved successfully"

# In the next request, read it
store.flash["notice"]  # => "Saved successfully"
```

## Same-Request Messages

To display a message in the current request (e.g., validation errors on form re-render):

```crystal
store.flash.now["error"] = "Validation failed"
```

## Convenience Accessors

| Accessor | Getter | Setter |
|----------|--------|--------|
| `notice` | `flash.notice` | `flash.notice = "msg"` |
| `alert` | `flash.alert` | `flash.alert = "msg"` |
| `error` | `flash.error` | `flash.error = "msg"` |
| `success` | `flash.success` | `flash.success = "msg"` |
| `warning` | `flash.warning` | `flash.warning = "msg"` |
| `info` | `flash.info` | `flash.info = "msg"` |

## Lifecycle Control

| Method | Description |
|--------|-------------|
| `keep(key)` | Preserve a message for one more request |
| `keep_all` | Preserve all messages for one more request |
| `discard(key)` | Remove a message from the next request |
| `discard_all` | Clear all messages from the next request |

```crystal
# Keep a notice around for an extra request (e.g., after redirect)
store.flash.keep("notice")
```

## Utility Methods

| Method | Return | Description |
|--------|--------|-------------|
| `[key]` | `String?` | Get message (checks `now` first, then `next`) |
| `[key]?` | `String?` | Same as `[]` |
| `has_key?(key)` | `Bool` | Check if message exists |
| `empty?` | `Bool` | True if no messages in either hash |
| `keys` | `Array(String)` | All unique keys across both hashes |

## See Also

- [Session Lifecycle](session-lifecycle.md)
- [Quick Start](../getting-started/quick-start.md)
