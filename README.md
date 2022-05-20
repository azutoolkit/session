# Session

[![Codacy Badge](https://api.codacy.com/project/badge/Grade/9a663614a1844a188270ba015cd14651)](https://app.codacy.com/gh/azutoolkit/session?utm_source=github.com&utm_medium=referral&utm_content=azutoolkit/session&utm_campaign=Badge_Grade_Settings) ![Crystal CI](https://github.com/azutoolkit/session/workflows/Crystal%20CI/badge.svg?branch=master)

A Strongly typed Session Management library to manage application sessions and state.

HTTP is a stateless protocol, and by default, HTTP requests are independent messages that don't retain user values. However, Session shard implements several approaches to bind and store user state data between requests.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     session:
       github: azutoolkit/session
   ```

2. Run `shards install`

## Configuration

```crystal
require "session"

Session.configure do |c|
  c.timeout = 1.hour
  c.session_key = "_session"
  s.secret = "Secret key for encryption"
  c.on_started = ->(sid : String, data : Databag) { puts "Session started - #{sid}" }
  c.on_deleted = ->(sid : String, data : Databag) { puts "Session Revoke - #{sid}" }
end
```

## Session Stores

The Session shard uses a store maintained by the app to persist data across requests from a client. The session data is backed by a cache and considered ephemeral data.

> **Recommendation:** The site should continue to function without the session data. Critical application data should be stored in the user database and cached in session only as a performance optimization.

The Session shard ships with three forms of session storage out of the box;

CookieStore, MemoryStore, and RedisStore.

### Cookie Store

The CookieStore is based on a Verifier and Encryptor, which encrypts and signs each cookie to ensure it can't be read or tampered with.

Since this store uses crypto features, you must set the `secret` field in the configuration.

```crystal
Session.configure do |c|
  ...
  s.secret = "Secret key for encryption"
  ...
end
```

After the secret is defined, you can instantiate the CookieStore provider

```crystal
module MyApp
  class_getter session = Session::CookieStore(UserSession).provider
end
```

### Memory Store

The memory store uses server memory and is the default for the session configuration.

We don't recommend using this store in production. Every session will be stored in MEMORY, and entries will not be removed upon expiration unless you create a task responsible for cleaning up old entries.

Also, sessions are not shared between servers.

```crystal
module MyApp
  class_getter session = Session::MemoryStore(UserSession).provider
end
```

### Redis Store

The RedisStore is recommended for production use as it is highly scalable and is shareable across multiple processes.

```crystal
module MyApp
  class_getter session = Session::RedisStore(UserSession).provider(client: Redis.new)
end
```

## Accessing Session Data

The Session shard offers type-safe access to the values stored in the session, meaning that to store values in the session, you must first define the object.

The shard calls this object a Databag.

### Databag Object

To define a Databag object

```crystal
# Type safe session contents
struct UserSession
  include Session::Databag
  property username : String? = "example"
end
```

To write and read to and from the `current_session`

```crystal
MyApp.session.data.username # Reads the value of the username property
MyApp.session.data.username = "Dark Vader" # Sets the value of the username property
```

### The Session API

```Crystal
MyApp.session.create           # Creates a new session
MyApp.session.storage          # Storage Type RedisStore or MemoryStore
MyApp.session.load_from        # Loads session from Cookie
MyApp.session.current_session  # Returns the current session
MyApp.session.session_id       # Returns the current session id
MyApp.session.delete           # Deletes the current session
MyApp.session.valid?           # Returns true if session has not expired
MyApp.session.cookie           # Returns a session cookie that can be sent to clients
MyApp.session[]                # Gets session by Session Id or raises an exception
MyApp.session[]?               # Gets session by Session Id or returns nil
MyApp.session.clear            # Removes all the sessions from store
```

> **Note:** Session also offers a _HTTP Handler_ `Session::SessionHandler` to
> automatically enable session management for the Application. Each request that
> passes through the Session Handlers resets the timeout for the cookie

## Roadmap - Help Wanted

- [ ] DbStore - Add Database session storage for PG, MySQL
- [ ] MongoStore - Add Mongo Database session storage
- [ ] CookieStore - Add Cookie Storage session storage (Must encrypt/decrypt value)
- [x] Session Created Event - Add event on session created
- [x] Session Deleted Event - Add event on session deleted

## Contributing

Contributions, issues, and feature requests are welcome!
Give a ⭐️ if you like this project!

1. Fork it (<https://github.com/azutoolkit/session/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Elias J. Perez](https://github.com/azutoolkit) - creator and maintainer
