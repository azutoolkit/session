module Session
  # Circuit Breaker states
  enum CircuitState
    Closed   # Normal operation - requests pass through
    Open     # Circuit tripped - requests fail fast
    HalfOpen # Testing if service recovered - allow one request
  end

  # Circuit Breaker configuration
  class CircuitBreakerConfig
    property failure_threshold : Int32 = 5
    property reset_timeout : Time::Span = 30.seconds
    property half_open_max_calls : Int32 = 1

    def initialize(
      @failure_threshold : Int32 = 5,
      @reset_timeout : Time::Span = 30.seconds,
      @half_open_max_calls : Int32 = 1,
    )
    end
  end

  # Circuit Breaker exception - raised when circuit is open
  class CircuitOpenException < Exception
    getter time_until_retry : Time::Span

    def initialize(@time_until_retry : Time::Span)
      super("Circuit breaker is open. Retry in #{@time_until_retry.total_seconds.to_i} seconds")
    end
  end

  # Circuit Breaker implementation for resilient service calls
  class CircuitBreaker
    getter state : CircuitState = CircuitState::Closed
    getter failure_count : Int32 = 0
    getter last_failure_time : Time? = nil
    getter config : CircuitBreakerConfig

    @mutex : Mutex = Mutex.new
    @half_open_calls : Int32 = 0

    def initialize(@config : CircuitBreakerConfig = CircuitBreakerConfig.new)
    end

    # Execute a block with circuit breaker protection
    def call(&block : -> T) : T forall T
      check_state!

      begin
        result = yield
        on_success
        result
      rescue ex : Exception
        on_failure(ex)
        raise ex
      end
    end

    # Check if circuit allows requests
    def allow_request? : Bool
      @mutex.synchronize do
        case @state
        when CircuitState::Closed
          true
        when CircuitState::Open
          should_attempt_reset?
        when CircuitState::HalfOpen
          @half_open_calls < @config.half_open_max_calls
        else
          false
        end
      end
    end

    # Manually reset the circuit breaker
    def reset!
      @mutex.synchronize do
        @state = CircuitState::Closed
        @failure_count = 0
        @last_failure_time = nil
        @half_open_calls = 0
      end
    end

    # Get time remaining until circuit retry
    def time_until_retry : Time::Span?
      @mutex.synchronize do
        return nil unless @state == CircuitState::Open
        return nil unless last_time = @last_failure_time

        elapsed = Time.local - last_time
        remaining = @config.reset_timeout - elapsed
        remaining > Time::Span.zero ? remaining : Time::Span.zero
      end
    end

    private def check_state!
      @mutex.synchronize do
        case @state
        when CircuitState::Open
          if should_attempt_reset?
            transition_to_half_open
          else
            remaining = time_until_retry_internal
            raise CircuitOpenException.new(remaining || 0.seconds)
          end
        when CircuitState::HalfOpen
          if @half_open_calls >= @config.half_open_max_calls
            remaining = time_until_retry_internal
            raise CircuitOpenException.new(remaining || 0.seconds)
          end
          @half_open_calls += 1
        end
      end
    end

    private def on_success
      @mutex.synchronize do
        case @state
        when CircuitState::HalfOpen
          # Success in half-open state - close the circuit
          Log.info { "Circuit breaker: Service recovered, closing circuit" }
          @state = CircuitState::Closed
          @failure_count = 0
          @half_open_calls = 0
        when CircuitState::Closed
          # Reset failure count on success
          @failure_count = 0
        end
      end
    end

    private def on_failure(ex : Exception)
      @mutex.synchronize do
        @failure_count += 1
        @last_failure_time = Time.local

        case @state
        when CircuitState::HalfOpen
          # Failure in half-open state - reopen the circuit
          Log.warn { "Circuit breaker: Service still failing, reopening circuit" }
          @state = CircuitState::Open
          @half_open_calls = 0
        when CircuitState::Closed
          if @failure_count >= @config.failure_threshold
            Log.warn { "Circuit breaker: Failure threshold reached (#{@failure_count}), opening circuit" }
            @state = CircuitState::Open
          end
        end
      end
    end

    private def should_attempt_reset? : Bool
      return false unless last_time = @last_failure_time
      Time.local - last_time >= @config.reset_timeout
    end

    private def transition_to_half_open
      Log.info { "Circuit breaker: Attempting recovery, entering half-open state" }
      @state = CircuitState::HalfOpen
      @half_open_calls = 0
    end

    private def time_until_retry_internal : Time::Span?
      return nil unless last_time = @last_failure_time
      elapsed = Time.local - last_time
      remaining = @config.reset_timeout - elapsed
      remaining > Time::Span.zero ? remaining : Time::Span.zero
    end
  end

  # Retry configuration for resilient operations
  class RetryConfig
    property max_attempts : Int32 = 3
    property base_delay : Time::Span = 100.milliseconds
    property max_delay : Time::Span = 5.seconds
    property backoff_multiplier : Float64 = 2.0
    property jitter : Float64 = 0.1

    def initialize(
      @max_attempts : Int32 = 3,
      @base_delay : Time::Span = 100.milliseconds,
      @max_delay : Time::Span = 5.seconds,
      @backoff_multiplier : Float64 = 2.0,
      @jitter : Float64 = 0.1,
    )
    end
  end

  # Retry utility for resilient operations
  module Retry
    extend self

    # Retry a block with exponential backoff
    def with_retry(
      config : RetryConfig = Session.config.retry_config,
      &block : -> T
    ) : T forall T
      last_exception : Exception? = nil

      config.max_attempts.times do |attempt|
        begin
          return yield
        rescue ex : Exception
          last_exception = ex

          # Don't retry on the last attempt
          break if attempt == config.max_attempts - 1

          # Calculate delay with exponential backoff and jitter
          delay = calculate_delay(attempt, config)

          Log.warn { "Retry attempt #{attempt + 1}/#{config.max_attempts} failed: #{ex.message}. Retrying in #{delay.total_milliseconds}ms" }

          sleep(delay)
        end
      end

      raise last_exception.as(Exception)
    end

    # Retry with custom retry condition
    def with_retry_if(
      should_retry : Exception -> Bool,
      config : RetryConfig = Session.config.retry_config,
      &block : -> T
    ) : T forall T
      last_exception : Exception? = nil

      config.max_attempts.times do |attempt|
        begin
          return yield
        rescue ex : Exception
          last_exception = ex

          # Check if we should retry this exception
          unless should_retry.call(ex)
            Log.debug { "Not retrying exception: #{ex.class} - #{ex.message}" }
            raise ex
          end

          # Don't retry on the last attempt
          break if attempt == config.max_attempts - 1

          # Calculate delay with exponential backoff and jitter
          delay = calculate_delay(attempt, config)

          Log.warn { "Retry attempt #{attempt + 1}/#{config.max_attempts} failed: #{ex.message}. Retrying in #{delay.total_milliseconds}ms" }

          sleep(delay)
        end
      end

      raise last_exception.as(Exception)
    end

    private def calculate_delay(attempt : Int32, config : RetryConfig) : Time::Span
      # Exponential backoff: base_delay * (backoff_multiplier ^ attempt)
      delay_ms = config.base_delay.total_milliseconds * (config.backoff_multiplier ** attempt)

      # Add jitter (±jitter% random variation)
      jitter_factor = 1.0 + (Random.new.next_float - 0.5) * 2 * config.jitter
      delay_ms *= jitter_factor

      # Cap at max_delay
      delay_ms = Math.min(delay_ms, config.max_delay.total_milliseconds)

      # Convert milliseconds to Time::Span
      (delay_ms / 1000.0).seconds
    end

    # Predicates for common retry scenarios
    def retryable_connection_error?(ex : Exception) : Bool
      case ex
      when IO::Error, Redis::ConnectionError, Redis::CommandTimeoutError
        true
      else
        false
      end
    end

    def retryable_timeout_error?(ex : Exception) : Bool
      case ex
      when IO::TimeoutError, Redis::CommandTimeoutError
        true
      else
        false
      end
    end

    def retryable_network_error?(ex : Exception) : Bool
      case ex
      when IO::Error, Redis::ConnectionError, Redis::CommandTimeoutError
        true
      else
        false
      end
    end
  end
end
