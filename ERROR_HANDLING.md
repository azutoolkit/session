# Error Handling & Resilience Improvements

This document outlines the comprehensive error handling and resilience improvements implemented in the Session management system.

## Overview

The Session system now includes robust error handling with specific exception types, retry mechanisms, and graceful degradation to ensure high availability and reliability.

## Exception Types

### Specific Exception Classes

The system now uses specific exception types instead of generic exceptions:

```crystal
# Session-specific exceptions
class SessionExpiredException < Exception
  def initialize(message : String = "Session has expired", cause : Exception? = nil)
    super(message, cause)
  end
end

class SessionCorruptionException < Exception
  def initialize(message : String = "Session data is corrupted", cause : Exception? = nil)
    super(message, cause)
  end
end

class StorageConnectionException < Exception
  def initialize(message : String = "Storage connection failed", cause : Exception? = nil)
    super(message, cause)
  end
end

class SessionNotFoundException < Exception
  def initialize(message : String = "Session not found", cause : Exception? = nil)
    super(message, cause)
  end
end

class SessionValidationException < Exception
  def initialize(message : String = "Session validation failed", cause : Exception? = nil)
    super(message, cause)
  end
end

class SessionSerializationException < Exception
  def initialize(message : String = "Session serialization failed", cause : Exception? = nil)
    super(message, cause)
  end
end

class SessionEncryptionException < Exception
  def initialize(message : String = "Session encryption/decryption failed", cause : Exception? = nil)
    super(message, cause)
  end
end
```

## Retry Mechanism

### Retry Configuration

The system includes a configurable retry mechanism with exponential backoff:

```crystal
class RetryConfig
  property max_attempts : Int32 = 3
  property base_delay : Time::Span = 100.milliseconds
  property max_delay : Time::Span = 5.seconds
  property backoff_multiplier : Float64 = 2.0
  property jitter : Float64 = 0.1
end
```

### Retry Usage

```crystal
# Basic retry with exponential backoff
Retry.with_retry(config) do
  # Operation that might fail
  redis_client.get(key)
end

# Retry with custom retry condition
Retry.with_retry_if(
  ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
  config
) do
  # Operation that might fail
  redis_client.set(key, value)
end
```

### Retry Predicates

```crystal
# Check if an exception is retryable
Retry.retryable_connection_error?(exception)
Retry.retryable_timeout_error?(exception)
Retry.retryable_network_error?(exception)
```

## Store-Specific Error Handling

### Redis Store Improvements

The Redis store now includes:

1. **Retry Logic**: Automatic retry for connection and timeout errors
2. **Specific Error Handling**: Different handling for different error types
3. **Graceful Degradation**: Fallback behavior when operations fail
4. **Health Monitoring**: Health check methods for monitoring

```crystal
def [](key : String) : T
  Retry.with_retry_if(
    ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
    Session.config.retry_config
  ) do
    if data = @client.get(prefixed(key))
      begin
        T.from_json(data)
      rescue ex : JSON::ParseException
        Log.error { "Failed to parse session data for key #{key}: #{ex.message}" }
        raise SessionCorruptionException.new("Invalid JSON in session data", ex)
      rescue ex : Exception
        Log.error { "Failed to deserialize session data for key #{key}: #{ex.message}" }
        raise SessionSerializationException.new("Session deserialization failed", ex)
      end
    else
      raise SessionNotFoundException.new("Session not found: #{key}")
    end
  end
rescue ex : Redis::ConnectionError | Redis::TimeoutError
  Log.error { "Redis connection error while retrieving session #{key}: #{ex.message}" }
  raise StorageConnectionException.new("Redis connection failed", ex)
rescue ex : Session::SessionExpiredException | Session::SessionCorruptionException | Session::SessionNotFoundException
  raise ex
rescue ex : Exception
  Log.error { "Unexpected error while retrieving session #{key}: #{ex.message}" }
  raise SessionValidationException.new("Session retrieval failed", ex)
end
```

### Memory Store Improvements

The memory store now includes:

1. **Expiration Handling**: Automatic cleanup of expired sessions
2. **Validation**: Session validation before storage
3. **Statistics**: Memory usage statistics
4. **Cleanup Methods**: Manual cleanup of expired sessions

```crystal
def [](key : String) : T
  if session = sessions[key]?
    if session.valid?
      session
    else
      # Clean up expired session
      sessions.delete(key)
      raise SessionExpiredException.new("Session has expired: #{key}")
    end
  else
    raise SessionNotFoundException.new("Session not found: #{key}")
  end
rescue ex : Session::SessionExpiredException | Session::SessionNotFoundException
  raise ex
rescue ex : Exception
  Log.error { "Unexpected error while retrieving session #{key}: #{ex.message}" }
  raise SessionValidationException.new("Session retrieval failed", ex)
end

# Clean up expired sessions
def cleanup_expired
  expired_keys = sessions.select { |_, session| !session.valid? }.keys
  expired_keys.each { |key| sessions.delete(key) }
  expired_keys.size
end

# Get memory usage statistics
def memory_stats
  {
    total_sessions: sessions.size,
    valid_sessions: sessions.count { |_, session| session.valid? },
    expired_sessions: sessions.count { |_, session| !session.valid? }
  }
end
```

### Cookie Store Improvements

The cookie store now includes:

1. **Encryption Error Handling**: Specific handling for encryption/decryption failures
2. **Validation**: Session validation before cookie creation
3. **Corruption Detection**: Detection and handling of corrupted session data
4. **Graceful Fallbacks**: Fallback behavior when encryption fails

```crystal
def [](key : String) : T
  if data = cookies[data_key]?
    begin
      payload = String.new(verify_and_decrypt(data.value))
      T.from_json payload
    rescue ex : Session::SessionEncryptionException
      Log.error { "Failed to decrypt session data: #{ex.message}" }
      raise SessionCorruptionException.new("Session data corruption detected", ex)
    rescue ex : JSON::ParseException
      Log.error { "Failed to parse session data: #{ex.message}" }
      raise SessionCorruptionException.new("Invalid session data format", ex)
    rescue ex : Exception
      Log.error { "Failed to deserialize session data: #{ex.message}" }
      raise SessionSerializationException.new("Session deserialization failed", ex)
    end
  else
    raise SessionNotFoundException.new("Session cookie not found")
  end
rescue ex : Session::SessionCorruptionException | Session::SessionSerializationException | Session::SessionNotFoundException
  raise ex
rescue ex : Exception
  Log.error { "Unexpected error while retrieving session: #{ex.message}" }
  raise SessionValidationException.new("Session retrieval failed", ex)
end
```

## HTTP Handler Error Handling

### Session Handler Improvements

The session handler now includes comprehensive error handling:

```crystal
def call(context : HTTP::Server::Context)
  begin
    @session.load_from(context.request.cookies)
  rescue ex : Session::SessionExpiredException
    Log.info { "Session expired for request #{context.request.resource}: #{ex.message}" }
    # Continue with request but session will be recreated
  rescue ex : Session::SessionCorruptionException
    Log.warn { "Session corruption detected for request #{context.request.resource}: #{ex.message}" }
    # Clear corrupted session and continue
    clear_corrupted_session(context)
  rescue ex : Session::StorageConnectionException
    Log.error { "Storage connection error for request #{context.request.resource}: #{ex.message}" }
    # Continue without session functionality
  rescue ex : Session::SessionValidationException
    Log.warn { "Session validation failed for request #{context.request.resource}: #{ex.message}" }
    # Continue with request but session will be recreated
  rescue ex : Exception
    Log.warn { "Failed to load session from cookies: #{ex.message}" }
    # Continue without session
  end

  call_next(context)

  begin
    @session.set_cookies(context.response.cookies, context.request.hostname.to_s)
  rescue ex : Session::SessionEncryptionException
    Log.error { "Failed to encrypt session cookies: #{ex.message}" }
    # Don't re-raise - cookies will be set without encryption
  rescue ex : Session::SessionValidationException
    Log.warn { "Failed to validate session for cookies: #{ex.message}" }
    # Don't re-raise - continue without setting cookies
  rescue ex : Exception
    Log.warn { "Failed to set session cookies: #{ex.message}" }
    # Don't re-raise - continue without cookies
  end
end
```

## Configuration

### Error Handling Configuration

```crystal
Session.configure do |c|
  # Retry configuration
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
end
```

## Best Practices

### 1. Exception Handling Strategy

- **Specific Exceptions**: Use specific exception types for different error scenarios
- **Graceful Degradation**: Always provide fallback behavior when possible
- **Logging**: Log errors with appropriate levels (error, warn, info)
- **No Silent Failures**: Avoid silent failures that could mask issues

### 2. Retry Strategy

- **Exponential Backoff**: Use exponential backoff to avoid overwhelming services
- **Jitter**: Add jitter to prevent thundering herd problems
- **Retryable Conditions**: Only retry on transient errors, not permanent failures
- **Maximum Attempts**: Set reasonable limits to prevent infinite retries

### 3. Monitoring and Observability

- **Health Checks**: Implement health check methods for monitoring
- **Metrics**: Track error rates and retry attempts
- **Logging**: Use structured logging for better analysis
- **Alerting**: Set up alerts for critical error conditions

### 4. Security Considerations

- **Error Information**: Don't expose sensitive information in error messages
- **Session Corruption**: Handle corrupted sessions securely
- **Encryption Failures**: Gracefully handle encryption/decryption failures
- **Validation**: Always validate session data before use

## Migration Guide

### From Generic Exceptions

If you were previously catching generic exceptions:

```crystal
# Before
begin
  session = store[key]
rescue ex : Exception
  # Generic error handling
end

# After
begin
  session = store[key]
rescue ex : Session::SessionExpiredException
  # Handle expired session
rescue ex : Session::SessionCorruptionException
  # Handle corrupted session
rescue ex : Session::StorageConnectionException
  # Handle connection issues
rescue ex : Session::SessionNotFoundException
  # Handle missing session
rescue ex : Exception
  # Handle unexpected errors
end
```

### Enabling Retry Logic

To enable retry logic for your operations:

```crystal
# Before
session = store[key]

# After
session = Retry.with_retry_if(
  ->(ex : Exception) { Retry.retryable_connection_error?(ex) },
  Session.config.retry_config
) do
  store[key]
end
```

## Testing Error Scenarios

### Unit Tests

```crystal
describe "Error Handling" do
  it "handles session expiration gracefully" do
    # Test expired session handling
  end

  it "retries on connection errors" do
    # Test retry logic
  end

  it "handles corrupted session data" do
    # Test corruption handling
  end

  it "gracefully degrades on storage failures" do
    # Test graceful degradation
  end
end
```

### Integration Tests

```crystal
describe "Resilience" do
  it "continues working when Redis is down" do
    # Test Redis failure scenarios
  end

  it "handles network timeouts" do
    # Test timeout scenarios
  end

  it "recovers from temporary failures" do
    # Test recovery scenarios
  end
end
```

## Conclusion

The error handling and resilience improvements provide:

1. **Better Reliability**: Specific error handling and retry mechanisms
2. **Improved Observability**: Comprehensive logging and monitoring
3. **Graceful Degradation**: Fallback behavior when components fail
4. **Security**: Secure handling of corrupted or invalid sessions
5. **Maintainability**: Clear exception types and error handling patterns

These improvements make the Session system more robust and suitable for production environments with high availability requirements.
