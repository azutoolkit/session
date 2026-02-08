# Quick Start

This guide walks you through creating your first session-enabled application.

## Step 1: Define Session Data

Create a class that extends `Session::Base`:

```crystal
require "session"

class UserSession < Session::Base
  property user_id : Int64?
  property username : String?
  property email : String?
  property role : String = "guest"
  property login_time : Time?

  def authenticated? : Bool
    !user_id.nil?
  end

  def admin? : Bool
    role == "admin"
  end
end
```

## Step 2: Configure Session

Set up the session configuration:

```crystal
Session.configure do |config|
  # Required: Secret key for encryption (use environment variable in production)
  config.secret = ENV["SESSION_SECRET"]? || "your-32-character-secret-key-here"

  # Session timeout
  config.timeout = 24.hours

  # Cookie name
  config.session_key = "myapp_session"

  # Choose a storage backend
  config.store = Session::MemoryStore(UserSession).new
end
```

## Step 3: Use Sessions

### Create a Session

```crystal
store = Session.config.store.not_nil!

# Create a new session
session = store.create

# Access session data
session.user_id = 12345
session.username = "alice"
session.email = "alice@example.com"
session.role = "admin"
session.login_time = Time.utc

puts "Session ID: #{session.session_id}"
puts "Username: #{session.username}"
puts "Is Admin: #{session.admin?}"
```

### Retrieve a Session

```crystal
# Get session by ID (raises if not found)
session = store[session_id]

# Get session by ID (returns nil if not found)
session = store[session_id]?
```

### Update a Session

```crystal
session = store[session_id]
session.role = "moderator"
store[session_id] = session  # Save changes
```

### Delete a Session

```crystal
store.delete(session_id)
```

## Step 4: HTTP Integration

Integrate with an HTTP server:

```crystal
require "http/server"
require "session"

# Configure session
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.store = Session::MemoryStore(UserSession).new
end

store = Session.config.store.not_nil!

# Create server with session handler
server = HTTP::Server.new([
  Session::SessionHandler.new(store),
]) do |context|
  case context.request.path
  when "/login"
    # Create session on login
    session = store.create
    session.user_id = 1
    session.username = "alice"
    store[session.session_id] = session
    context.response.print "Logged in as alice"

  when "/profile"
    # Access session data
    if store.valid? && store.current_session.authenticated?
      context.response.print "Hello, #{store.current_session.username}!"
    else
      context.response.status = HTTP::Status::UNAUTHORIZED
      context.response.print "Please log in"
    end

  when "/logout"
    # Destroy session
    store.delete
    context.response.print "Logged out"

  else
    context.response.print "Welcome!"
  end
end

puts "Server running on http://localhost:8080"
server.listen(8080)
```

## Step 5: Add Flash Messages

Use flash messages for one-time notifications:

```crystal
# Set flash message (available on next request)
store.flash["notice"] = "Your changes have been saved!"
store.flash["error"] = "Something went wrong."

# In next request, access flash messages
if notice = store.flash.now["notice"]?
  puts "Notice: #{notice}"
end
```

## Complete Example

```crystal
require "session"
require "http/server"

# Define session data
class UserSession < Session::Base
  property user_id : Int64?
  property username : String?

  def authenticated? : Bool
    !user_id.nil?
  end
end

# Configure
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]? || "dev-secret-32-characters-long!!"
  config.timeout = 1.hour
  config.sliding_expiration = true
  config.store = Session::MemoryStore(UserSession).new
end

store = Session.config.store.not_nil!

# Server
server = HTTP::Server.new([
  Session::SessionHandler.new(store),
]) do |context|
  # Your application logic here
  context.response.content_type = "text/html"
  context.response.print <<-HTML
    <h1>Session Demo</h1>
    <p>Session ID: #{store.session_id}</p>
    <p>Authenticated: #{store.current_session.authenticated?}</p>
    <p>Username: #{store.current_session.username || "Guest"}</p>
  HTML
end

server.listen(8080)
```

## Next Steps

- [Configuration](../configuration/basic.md) - Explore all configuration options
- [Storage Backends](../storage-backends/overview.md) - Choose the right backend
- [Clustering](../clustering/overview.md) - Scale to multiple nodes
