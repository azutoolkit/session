# Error Handling and Resilience Example
# This example demonstrates how to use the new error handling features

require "../src/session"

# Define a session data structure
struct UserSession
  include Session::SessionData

  property user_id : Int64?
  property username : String?
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

# Configure session with error handling
Session.configure do |c|
  # Configure retry settings
  c.retry_config = Session::RetryConfig.new(
    max_attempts: 3,
    base_delay: 100.milliseconds,
    max_delay: 5.seconds,
    backoff_multiplier: 2.0,
    jitter: 0.1
  )

  # Error handling configuration
  c.enable_retry = true
  c.log_errors = true
  c.fail_fast_on_corruption = true

  # Set up Redis store with error handling
  c.provider = Session::RedisStore(UserSession).provider(client: Redis.new)
end

# Example: Handling session operations with error handling
class SessionManager
  @session : Session::Provider

  def initialize(@session = Session.session)
  end

  # Example: Create session with error handling
  def create_user_session(user_id : Int64, username : String) : Bool
    begin
      session = @session.create
      session.data.user_id = user_id
      session.data.username = username
      session.data.last_login = Time.utc
      session.data.reset_login_attempts

      Log.info { "Created session for user #{username}" }
      true
    rescue ex : Session::SessionValidationException
      Log.error { "Failed to create session: #{ex.message}" }
      false
    rescue ex : Session::StorageConnectionException
      Log.error { "Storage connection failed: #{ex.message}" }
      false
    rescue ex : Exception
      Log.error { "Unexpected error creating session: #{ex.message}" }
      false
    end
  end

  # Example: Load session with error handling
  def load_user_session : UserSession?
    begin
      @session.load_from(HTTP::Cookies.new) # In real app, pass actual cookies
      @session.data
    rescue ex : Session::SessionExpiredException
      Log.info { "Session expired, creating new session" }
      create_new_session
    rescue ex : Session::SessionCorruptionException
      Log.warn { "Session corrupted, clearing and creating new session" }
      clear_corrupted_session
      create_new_session
    rescue ex : Session::SessionNotFoundException
      Log.info { "No session found, creating new session" }
      create_new_session
    rescue ex : Session::StorageConnectionException
      Log.error { "Storage connection failed: #{ex.message}" }
      nil
    rescue ex : Exception
      Log.error { "Unexpected error loading session: #{ex.message}" }
      nil
    end
  end

  # Example: Update session with retry logic
  def update_session_data(updates : Hash(String, String)) : Bool
    Session::Retry.with_retry_if(
      ->(ex : Exception) { Session::Retry.retryable_connection_error?(ex) },
      Session.config.retry_config
    ) do
      updates.each do |key, value|
        case key
        when "username"
          @session.data.username = value
        when "mfa_verified"
          @session.data.mfa_verified = value == "true"
        end
      end
      true
    end
  rescue ex : Session::StorageConnectionException
    Log.error { "Failed to update session after retries: #{ex.message}" }
    false
  rescue ex : Exception
    Log.error { "Unexpected error updating session: #{ex.message}" }
    false
  end

  # Example: Delete session with error handling
  def delete_user_session : Bool
    begin
      @session.delete
      Log.info { "Deleted user session" }
      true
    rescue ex : Session::StorageConnectionException
      Log.warn { "Storage connection failed during deletion: #{ex.message}" }
      # Session will expire naturally, so this is not critical
      true
    rescue ex : Exception
      Log.warn { "Error deleting session: #{ex.message}" }
      false
    end
  end

  # Example: Check session health
  def check_session_health : Bool
    begin
      if store = @session.as?(Session::RedisStore(UserSession))
        store.healthy?
      else
        true # Memory store is always healthy
      end
    rescue ex : Exception
      Log.warn { "Health check failed: #{ex.message}" }
      false
    end
  end

  # Example: Clean up expired sessions (for memory store)
  def cleanup_expired_sessions : Int32
    if store = @session.as?(Session::MemoryStore(UserSession))
      store.cleanup_expired
    else
      0
    end
  rescue ex : Exception
    Log.warn { "Failed to cleanup expired sessions: #{ex.message}" }
    0
  end

  # Example: Get session statistics
  def get_session_stats : Hash(String, Int32)
    if store = @session.as?(Session::MemoryStore(UserSession))
      stats = store.memory_stats
      {
        "total_sessions"   => stats[:total_sessions],
        "valid_sessions"   => stats[:valid_sessions],
        "expired_sessions" => stats[:expired_sessions],
      }
    else
      {"total_sessions" => 0, "valid_sessions" => 0, "expired_sessions" => 0}
    end
  rescue ex : Exception
    Log.warn { "Failed to get session stats: #{ex.message}" }
    {"total_sessions" => 0, "valid_sessions" => 0, "expired_sessions" => 0}
  end

  private def create_new_session : UserSession?
    begin
      @session.create
      @session.data
    rescue ex : Exception
      Log.error { "Failed to create new session: #{ex.message}" }
      nil
    end
  end

  private def clear_corrupted_session
    begin
      @session.delete
    rescue ex : Exception
      Log.warn { "Failed to clear corrupted session: #{ex.message}" }
    end
  end
end

# Example: HTTP handler with comprehensive error handling
class ResilientSessionHandler
  include HTTP::Handler

  def initialize(@session_manager : SessionManager)
  end

  def call(context : HTTP::Server::Context)
    # Load session with error handling
    user_session = @session_manager.load_user_session

    if user_session
      Log.debug { "Loaded session for user: #{user_session.username}" }
    else
      Log.debug { "No valid session found" }
    end

    # Process the request
    call_next(context)

    # Handle session updates based on response
    handle_session_updates(context, user_session)
  rescue ex : Exception
    Log.error { "Unexpected error in session handler: #{ex.message}" }
    # Continue processing to avoid breaking the application
    call_next(context)
  end

  private def handle_session_updates(context : HTTP::Server::Context, user_session : UserSession?)
    # Example: Update session based on response status
    case context.response.status_code
    when 401
      # Unauthorized - increment login attempts
      if user_session
        user_session.increment_login_attempts
        Log.info { "Incremented login attempts for user: #{user_session.username}" }
      end
    when 200
      # Success - reset login attempts
      if user_session
        user_session.reset_login_attempts
        Log.debug { "Reset login attempts for user: #{user_session.username}" }
      end
    end
  rescue ex : Exception
    Log.warn { "Failed to update session: #{ex.message}" }
  end
end

# Example: Usage in a web application
puts "Error Handling and Resilience Example"
puts "====================================="

# Create session manager
session_manager = SessionManager.new

# Example: Create a user session
puts "\n1. Creating user session..."
if session_manager.create_user_session(123_i64, "john_doe")
  puts "✓ Session created successfully"
else
  puts "✗ Failed to create session"
end

# Example: Load session
puts "\n2. Loading user session..."
if user_session = session_manager.load_user_session
  puts "✓ Session loaded: #{user_session.username}"
else
  puts "✗ Failed to load session"
end

# Example: Update session with retry
puts "\n3. Updating session data..."
updates = {"username" => "john_updated", "mfa_verified" => "true"}
if session_manager.update_session_data(updates)
  puts "✓ Session updated successfully"
else
  puts "✗ Failed to update session"
end

# Example: Check session health
puts "\n4. Checking session health..."
if session_manager.check_session_health
  puts "✓ Session storage is healthy"
else
  puts "✗ Session storage health check failed"
end

# Example: Get session statistics
puts "\n5. Getting session statistics..."
stats = session_manager.get_session_stats
puts "Session stats: #{stats}"

# Example: Clean up expired sessions
puts "\n6. Cleaning up expired sessions..."
cleaned = session_manager.cleanup_expired_sessions
puts "Cleaned up #{cleaned} expired sessions"

# Example: Delete session
puts "\n7. Deleting user session..."
if session_manager.delete_user_session
  puts "✓ Session deleted successfully"
else
  puts "✗ Failed to delete session"
end

puts "\nExample completed!"
