# Quick Start

This guide walks you through creating your first session-enabled application.

## Step 1: Define Session Data

Create a struct that includes `Session::SessionData`:

```crystal
require "session"

struct UserSession
  include Session::SessionData

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
  config.provider = Session::MemoryStore(UserSession).provider
end
```

## Step 3: Use Sessions

### Create a Session

```crystal
provider = Session.provider

# Create a new session
session = provider.create

# Access session data
session.data.user_id = 12345
session.data.username = "alice"
session.data.email = "alice@example.com"
session.data.role = "admin"
session.data.login_time = Time.utc

puts "Session ID: #{session.session_id}"
puts "Username: #{session.data.username}"
puts "Is Admin: #{session.data.admin?}"
```

### Retrieve a Session

```crystal
# Get session by ID (raises if not found)
session = provider[session_id]

# Get session by ID (returns nil if not found)
session = provider[session_id]?
```

### Update a Session

```crystal
session = provider[session_id]
session.data.role = "moderator"
provider[session_id] = session  # Save changes
```

### Delete a Session

```crystal
provider.delete(session_id)
```

## Step 4: HTTP Integration

Integrate with an HTTP server:

```crystal
require "http/server"
require "session"

# Configure session
Session.configure do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.provider = Session::MemoryStore(UserSession).provider
end

# Create server with session handler
server = HTTP::Server.new([
  Session::SessionHandler.new(Session.provider),
]) do |context|
  provider = Session.provider

  case context.request.path
  when "/login"
    # Create session on login
    session = provider.create
    session.data.user_id = 1
    session.data.username = "alice"
    provider[session.session_id] = session
    context.response.print "Logged in as alice"

  when "/profile"
    # Access session data
    if provider.valid? && provider.data.authenticated?
      context.response.print "Hello, #{provider.data.username}!"
    else
      context.response.status = HTTP::Status::UNAUTHORIZED
      context.response.print "Please log in"
    end

  when "/logout"
    # Destroy session
    provider.delete
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
provider.flash["notice"] = "Your changes have been saved!"
provider.flash["error"] = "Something went wrong."

# In next request, access flash messages
if notice = provider.flash.now["notice"]?
  puts "Notice: #{notice}"
end
```

## Complete Example

```crystal
require "session"
require "http/server"

# Define session data
struct UserSession
  include Session::SessionData
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
  config.provider = Session::MemoryStore(UserSession).provider
end

# Server
server = HTTP::Server.new([
  Session::SessionHandler.new(Session.provider),
]) do |context|
  provider = Session.provider

  # Your application logic here
  context.response.content_type = "text/html"
  context.response.print <<-HTML
    <h1>Session Demo</h1>
    <p>Session ID: #{provider.session_id}</p>
    <p>Authenticated: #{provider.data.authenticated?}</p>
    <p>Username: #{provider.data.username || "Guest"}</p>
  HTML
end

server.listen(8080)
```

## Next Steps

- [Configuration](../configuration/basic.md) - Explore all configuration options
- [Storage Backends](../storage-backends/overview.md) - Choose the right backend
- [Clustering](../clustering/overview.md) - Scale to multiple nodes
