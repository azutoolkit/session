module Session
  module Metrics
    # Abstract metrics backend - implement this to integrate with your metrics system
    abstract class Backend
      # Record a counter increment
      abstract def increment(name : String, tags : Hash(String, String) = {} of String => String) : Nil

      # Record a timing/duration
      abstract def timing(name : String, duration : Time::Span, tags : Hash(String, String) = {} of String => String) : Nil

      # Record a gauge value
      abstract def gauge(name : String, value : Float64, tags : Hash(String, String) = {} of String => String) : Nil
    end

    # Null backend - discards all metrics (default)
    class NullBackend < Backend
      def increment(name : String, tags : Hash(String, String) = {} of String => String) : Nil
      end

      def timing(name : String, duration : Time::Span, tags : Hash(String, String) = {} of String => String) : Nil
      end

      def gauge(name : String, value : Float64, tags : Hash(String, String) = {} of String => String) : Nil
      end
    end

    # Log backend - logs all metrics to the session logger
    class LogBackend < Backend
      def increment(name : String, tags : Hash(String, String) = {} of String => String) : Nil
        Session::Log.info { "METRIC increment: #{name} #{format_tags(tags)}" }
      end

      def timing(name : String, duration : Time::Span, tags : Hash(String, String) = {} of String => String) : Nil
        Session::Log.info { "METRIC timing: #{name}=#{duration.total_milliseconds}ms #{format_tags(tags)}" }
      end

      def gauge(name : String, value : Float64, tags : Hash(String, String) = {} of String => String) : Nil
        Session::Log.info { "METRIC gauge: #{name}=#{value} #{format_tags(tags)}" }
      end

      private def format_tags(tags : Hash(String, String)) : String
        return "" if tags.empty?
        tags.map { |k, v| "#{k}=#{v}" }.join(" ")
      end
    end

    # Metric names as constants for consistency
    module Names
      SESSION_CREATED           = "session.created"
      SESSION_LOADED            = "session.loaded"
      SESSION_DELETED           = "session.deleted"
      SESSION_REGENERATED       = "session.regenerated"
      SESSION_EXPIRED           = "session.expired"
      SESSION_ERROR             = "session.error"
      SESSION_LOAD_TIME         = "session.load_time"
      SESSION_STORE_TIME        = "session.store_time"
      SESSION_ACTIVE_COUNT      = "session.active_count"
      CIRCUIT_BREAKER_OPEN      = "session.circuit_breaker.open"
      CIRCUIT_BREAKER_HALF_OPEN = "session.circuit_breaker.half_open"
      RETRY_ATTEMPT             = "session.retry.attempt"
    end

    # Helper module to record common session metrics
    module Helper
      extend self

      def record_created(store_type : String)
        backend.increment(Names::SESSION_CREATED, {"store" => store_type})
      end

      def record_loaded(store_type : String)
        backend.increment(Names::SESSION_LOADED, {"store" => store_type})
      end

      def record_deleted(store_type : String)
        backend.increment(Names::SESSION_DELETED, {"store" => store_type})
      end

      def record_regenerated(store_type : String)
        backend.increment(Names::SESSION_REGENERATED, {"store" => store_type})
      end

      def record_expired(store_type : String)
        backend.increment(Names::SESSION_EXPIRED, {"store" => store_type})
      end

      def record_error(store_type : String, error_type : String)
        backend.increment(Names::SESSION_ERROR, {"store" => store_type, "error" => error_type})
      end

      def record_load_time(store_type : String, duration : Time::Span)
        backend.timing(Names::SESSION_LOAD_TIME, duration, {"store" => store_type})
      end

      def record_store_time(store_type : String, duration : Time::Span)
        backend.timing(Names::SESSION_STORE_TIME, duration, {"store" => store_type})
      end

      def record_active_count(store_type : String, count : Int64)
        backend.gauge(Names::SESSION_ACTIVE_COUNT, count.to_f64, {"store" => store_type})
      end

      def time_operation(store_type : String, operation : String, &block : -> T) : T forall T
        start_time = Time.monotonic
        begin
          result = yield
          duration = Time.monotonic - start_time
          case operation
          when "load"
            record_load_time(store_type, duration)
          when "store"
            record_store_time(store_type, duration)
          end
          result
        rescue ex
          duration = Time.monotonic - start_time
          record_error(store_type, ex.class.name)
          raise ex
        end
      end

      private def backend : Backend
        Session.config.metrics_backend
      end
    end
  end
end
