require "./spec_helper"

describe Session::Metrics do
  describe Session::Metrics::NullBackend do
    it "accepts increment calls" do
      backend = Session::Metrics::NullBackend.new
      backend.increment("test.counter")
      backend.increment("test.counter", {"tag" => "value"})
      # Should not raise
    end

    it "accepts timing calls" do
      backend = Session::Metrics::NullBackend.new
      backend.timing("test.timing", 100.milliseconds)
      backend.timing("test.timing", 1.second, {"tag" => "value"})
      # Should not raise
    end

    it "accepts gauge calls" do
      backend = Session::Metrics::NullBackend.new
      backend.gauge("test.gauge", 42.0)
      backend.gauge("test.gauge", 3.14, {"tag" => "value"})
      # Should not raise
    end
  end

  describe Session::Metrics::LogBackend do
    it "logs increment calls" do
      backend = Session::Metrics::LogBackend.new
      backend.increment("test.counter")
      backend.increment("test.counter", {"store" => "memory"})
      # Should log without error
    end

    it "logs timing calls" do
      backend = Session::Metrics::LogBackend.new
      backend.timing("test.timing", 150.milliseconds)
      backend.timing("test.timing", 2.seconds, {"operation" => "load"})
      # Should log without error
    end

    it "logs gauge calls" do
      backend = Session::Metrics::LogBackend.new
      backend.gauge("test.gauge", 100.0)
      backend.gauge("test.gauge", 50.5, {"type" => "active"})
      # Should log without error
    end
  end

  describe Session::Metrics::Names do
    it "defines session metric names" do
      Session::Metrics::Names::SESSION_CREATED.should eq "session.created"
      Session::Metrics::Names::SESSION_LOADED.should eq "session.loaded"
      Session::Metrics::Names::SESSION_DELETED.should eq "session.deleted"
      Session::Metrics::Names::SESSION_REGENERATED.should eq "session.regenerated"
      Session::Metrics::Names::SESSION_EXPIRED.should eq "session.expired"
      Session::Metrics::Names::SESSION_ERROR.should eq "session.error"
    end

    it "defines timing metric names" do
      Session::Metrics::Names::SESSION_LOAD_TIME.should eq "session.load_time"
      Session::Metrics::Names::SESSION_STORE_TIME.should eq "session.store_time"
    end

    it "defines gauge metric names" do
      Session::Metrics::Names::SESSION_ACTIVE_COUNT.should eq "session.active_count"
    end

    it "defines circuit breaker metric names" do
      Session::Metrics::Names::CIRCUIT_BREAKER_OPEN.should eq "session.circuit_breaker.open"
      Session::Metrics::Names::CIRCUIT_BREAKER_HALF_OPEN.should eq "session.circuit_breaker.half_open"
    end
  end

  describe Session::Metrics::Helper do
    it "records created metric" do
      Session.config.metrics_backend = Session::Metrics::NullBackend.new
      Session::Metrics::Helper.record_created("MemoryStore")
      # Should not raise
    end

    it "records loaded metric" do
      Session.config.metrics_backend = Session::Metrics::NullBackend.new
      Session::Metrics::Helper.record_loaded("MemoryStore")
      # Should not raise
    end

    it "records error metric" do
      Session.config.metrics_backend = Session::Metrics::NullBackend.new
      Session::Metrics::Helper.record_error("MemoryStore", "ConnectionError")
      # Should not raise
    end

    it "records timing metrics" do
      Session.config.metrics_backend = Session::Metrics::NullBackend.new
      Session::Metrics::Helper.record_load_time("MemoryStore", 50.milliseconds)
      Session::Metrics::Helper.record_store_time("MemoryStore", 25.milliseconds)
      # Should not raise
    end

    it "records active count" do
      Session.config.metrics_backend = Session::Metrics::NullBackend.new
      Session::Metrics::Helper.record_active_count("MemoryStore", 42_i64)
      # Should not raise
    end

    describe ".time_operation" do
      it "times successful operations" do
        Session.config.metrics_backend = Session::Metrics::NullBackend.new

        result = Session::Metrics::Helper.time_operation("MemoryStore", "load") do
          sleep 1.millisecond
          "success"
        end

        result.should eq "success"
      end

      it "times and records errors" do
        Session.config.metrics_backend = Session::Metrics::NullBackend.new

        expect_raises(Exception, "test error") do
          Session::Metrics::Helper.time_operation("MemoryStore", "load") do
            raise "test error"
          end
        end
      end
    end
  end
end
