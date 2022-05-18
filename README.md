# Session

[![Codacy Badge](https://api.codacy.com/project/badge/Grade/9a663614a1844a188270ba015cd14651)](https://app.codacy.com/gh/azutoolkit/session?utm_source=github.com&utm_medium=referral&utm_content=azutoolkit/session&utm_campaign=Badge_Grade_Settings) ![Crystal CI](https://github.com/azutoolkit/session/workflows/Crystal%20CI/badge.svg?branch=master)

A Strongly typed Session Management library to manage application session and state.

HTTP is a stateless protocol, and by default, HTTP requests are independent messages
that don't retain user values. However, Session shard implements several approaches
to bind and store user state data between requests.

The Session shard uses a store maintained by the app to persist data across requests from
a client. The session data is backed by a cache and considered ephemeral data.
The site should continue to function without the session data. Critical application
data should be stored in the user database and cached in session only as a
performance optimization.

A cookie provides the Session state to the client that contains the session ID.

The cookie session ID:

- The client sends the session cookie to the app on each request is then
  used to reconstruct the session
- The app uses the session cookie to fetch the session data.

Session state exhibits the following behaviors:

- The session cookie is specific to the client or browser and not
  shared across clients
- When the browser session ends, the client cookie is deleted.
- Empty sessions are not persisted.
- The session must have at least one value set to persist across requests.
  When a session data is empty new session ID is generated for each request.

The app retains a session for a limited time after the last request. After that,
the app either sets the session timeout or uses the default value of 20 minutes.

The Session shard is ideal for storing user data:

- That's specific to a particular session where the data doesn't require
  permanent storage across sessions.
- Deletes session data either when the App invokes the `YourApp.session.delete` or
  when the session expires.
- There's no default mechanism to inform app code that a client browser has been
  closed or when the session cookie is deleted or expired on the client.
- Session state cookies are not marked essential by default. Session state isn't
  functional unless the site visitor permits tracking.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     session:
       github: azutoolkit/session
   ```

2. Run `shards install`

## Usage

```crystal
require "session"

Session.configure do
  timeout = 1.hour
  session_key = "_session"
  on_started = ->(sid : String, data : Databag) { puts "Session started - #{sid}" }
  on_deleted = ->(sid : String, data : Databag) { puts "Session Revoke - #{sid}" }
end

# Type safe session contents
class UserSession
  include Session::Databag
  property username : String? = "example"
end

# Memory Store
module MyApp
  class_getter session = Session::MemoryStore(Databag).provider
end

# Redis Store
module MyApp
  class_getter session = Session::RedisStore(Databag).provider(client: Redis.new)
end
```

### The Session API

```Crystal
MyApp.session.create           # Creates a new session
MyApp.session.storage          # Storage Type RedisStore or MemoryStore
MyApp.session.load_from        # Loads session from Cookie
MyApp.session.username         # Access databag properties
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
