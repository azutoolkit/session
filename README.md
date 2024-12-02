# Session

[![Codacy Badge](https://api.codacy.com/project/badge/Grade/9a663614a1844a188270ba015cd14651)](https://app.codacy.com/gh/azutoolkit/session?utm_source=github.com&utm_medium=referral&utm_content=azutoolkit/session&utm_campaign=Badge_Grade_Settings) ![Crystal CI](https://github.com/azutoolkit/session/workflows/Crystal%20CI/badge.svg?branch=master)

A Strongly typed Session Management library to manage application sessions and state.

HTTP is a stateless protocol, and by default, HTTP requests are independent messages that don't retain user values. However, Session shard implements several approaches to bind and store user state data between requests.

# Table of contents

- [Session](#session)
- [Table of contents](#table-of-contents)
  - [Installation](#installation)
  - [Configuration](#configuration)
  - [Session Stores](#session-stores)
    - [Cookie Store](#cookie-store)
    - [Memory Store](#memory-store)
    - [Redis Store](#redis-store)
  - [Accessing Session Data](#accessing-session-data)
    - [SessionData Object](#sessiondata-object)
  - [Security Features](#security-features)
    - [Authentication](#authentication)
    - [Compliance](#compliance)
    - [Session Expiry and Revocation](#session-expiry-and-revocation)
    - [The Session API](#the-session-api)
  - [Session HTTP Handler](#session-http-handler)
  - [Roadmap - Help Wanted](#roadmap---help-wanted)
  - [Contributing](#contributing)
  - [Contributors](#contributors)

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
  c.on_started = ->(sid : String, data : SessionData) { puts "Session started - #{sid}" }
  c.on_deleted = ->(sid : String, data : SessionData) { puts "Session Revoke - #{sid}" }
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
  c.timeout = 1.hour
  c.secret = "Secret key for encryption"
  c.session_key = "myapp.session"
  c.provider = Session::CookieStore(Sessions::UserSession).provider
  c.on_started = ->(sid : String, data : Session::SessionData) { puts "Session started - #{sid}" }
  c.on_deleted = ->(sid : String, data : Session::SessionData) { puts "Session Revoke - #{sid}" }
end
```

After the secret is defined, you can instantiate the CookieStore provider

```crystal
module MyApp
  def self.session
    Session.session?.not_nil!
  end
end
```

### Memory Store

The memory store uses server memory and is the default for the session configuration.

We don't recommend using this store in production. Every session will be stored in MEMORY, and the shard will not remove session entries upon expiration unless you create a task responsible for cleaning up expired entries.

Also, multiple servers cannot share the stored sessions.

```crystal
Session.configure do |c|
  c.provider = Session::MemoryStore(UserSession).provider
end
```

### Redis Store

The RedisStore is recommended for production use as it is highly scalable and is shareable across multiple processes.

```crystal
Session.configure do |c|
  c.provider = Session::RedisStore(UserSession).provider(client: Redis.new)
end
```

## Accessing Session Data

The Session shard offers type-safe access to the values stored in the session, meaning that to store values in the session, you must first define the object.

The shard calls this object a SessionData.

### SessionData Object

To define a SessionData object

```crystal
# Type safe session contents
struct UserSession
  include Session::SessionData
  property username : String? = "example"
end
```

To write and read to and from the `current_session`

```crystal
MyApp.session.data.username # Reads the value of the username property
MyApp.session.data.username = "Dark Vader" # Sets the value of the username property
```

## Security Features

### Authentication

The Session shard provides comprehensive authentication capabilities:

```crystal
struct UserSession
  include Session::SessionData

  property user_id : Int64?
  property login_attempts : Int32 = 0
  property last_login : Time?
  property mfa_verified : Bool = false

  def authenticated? : Bool
    !user_id.nil? && (!mfa_required? || mfa_verified)
  end

  def mfa_required? : Bool
    # Implement your MFA requirement logic
    true
  end

  def increment_login_attempts
    @login_attempts += 1
  end

  def reset_login_attempts
    @login_attempts = 0
  end
end

class AuthenticationHandler
  def login(email : String, password : String)
    return false if session.data.login_attempts >= 5

    if user = authenticate_user(email, password)
      session.data.user_id = user.id
      session.data.last_login = Time.utc
      session.data.reset_login_attempts
      true
    else
      session.data.increment_login_attempts
      false
    end
  end

  def logout
    session.delete
  end
end
```

### Compliance

GDPR and HIPAA compliance features:

```crystal
struct CompliantSession
  include Session::SessionData

  # Audit logging
  property last_accessed_at : Time = Time.utc
  property access_log : Array(AccessLog) = [] of AccessLog

  # Consent management
  property privacy_policy_accepted : Bool = false
  property privacy_policy_version : String?
  property marketing_consent : Bool = false

  # Data encryption
  property encrypted_data : Hash(String, String) = {} of String => String

  def log_access(action : String, ip_address : String)
    access_log << AccessLog.new(
      action: action,
      ip_address: ip_address,
      timestamp: Time.utc
    )
  end

  def store_encrypted(key : String, value : String)
    encrypted_data[key] = Encryption.encrypt(value, Session.config.secret)
  end

  def retrieve_encrypted(key : String) : String?
    encrypted_data[key]?.try { |v| Encryption.decrypt(v, Session.config.secret) }
  end
end
```

### Session Expiry and Revocation

Comprehensive session management:

```crystal
struct ExpiringSession
  include Session::SessionData

  property absolute_timeout : Time
  property idle_timeout : Time
  property revoked : Bool = false

  def initialize
    @absolute_timeout = 24.hours.from_now
    @idle_timeout = 30.minutes.from_now
  end

  def valid? : Bool
    !revoked && Time.utc < absolute_timeout && Time.utc < idle_timeout
  end

  def extend_idle_timeout
    @idle_timeout = 30.minutes.from_now
  end

  def revoke
    @revoked = true
  end
end

# Usage in handlers
class SessionHandler
  def handle_request
    return unless session = current_session

    if session.valid?
      session.extend_idle_timeout
    else
      session.delete
    end
  end
end
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

## Session HTTP Handler

A very simple HTTP handler enables session management for an HTTP application that writes and reads session cookies.

```crystal
module Session
  class SessionHandler
    include HTTP::Handler

    def initialize(@session : Session::Provider)
    end

    def call(context : HTTP::Server::Context)
      @session.load_from context.request.cookies
      call_next(context)
      @session.set_cookies context.response.cookies
    end
  end
end
```

## Roadmap - Help Wanted

- [ ] DbStore - Add Database session storage for PG, MySQL
- [ ] MongoStore - Add Mongo Database session storage
- [x] CookieStore - Add Cookie Storage session storage (Must encrypt/decrypt value)
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
