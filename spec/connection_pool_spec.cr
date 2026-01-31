require "./spec_helper"

describe Session::ConnectionPoolConfig do
  it "has sensible defaults" do
    config = Session::ConnectionPoolConfig.new
    config.size.should eq 5
    config.timeout.should eq 5.seconds
    config.redis_host.should eq "localhost"
    config.redis_port.should eq 6379
    config.redis_database.should eq 0
    config.redis_password.should be_nil
  end

  it "accepts custom values" do
    config = Session::ConnectionPoolConfig.new(
      size: 10,
      timeout: 10.seconds,
      redis_host: "redis.example.com",
      redis_port: 6380,
      redis_database: 2,
      redis_password: "secret"
    )
    config.size.should eq 10
    config.timeout.should eq 10.seconds
    config.redis_host.should eq "redis.example.com"
    config.redis_port.should eq 6380
    config.redis_database.should eq 2
    config.redis_password.should eq "secret"
  end
end

describe Session::ConnectionPoolTimeoutException do
  it "includes timeout in message" do
    ex = Session::ConnectionPoolTimeoutException.new(5.seconds)
    ex.message.to_s.should contain("5.0 seconds")
  end
end

if REDIS_AVAILABLE
  describe Session::ConnectionPool do
    it "creates pool with configured size" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      pool = Session::ConnectionPool.new(config)

      pool.size.should eq 2
      pool.available.should eq 2

      pool.shutdown
    end

    it "executes block with a connection via #with_connection" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      pool = Session::ConnectionPool.new(config)

      result = pool.with_connection do |conn|
        conn.ping
      end

      result.should eq "PONG"
      pool.shutdown
    end

    it "returns connection to pool after #with_connection" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      pool = Session::ConnectionPool.new(config)

      pool.with_connection(&.ping)

      stats = pool.stats
      stats[:available].should eq 2
      stats[:in_use].should eq 0

      pool.shutdown
    end

    it "reports correct stats during checkout" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      pool = Session::ConnectionPool.new(config)

      conn = pool.checkout
      stats = pool.stats
      stats[:size].should eq 2
      stats[:available].should eq 1
      stats[:in_use].should eq 1

      pool.checkin(conn)
      stats = pool.stats
      stats[:available].should eq 2
      stats[:in_use].should eq 0

      pool.shutdown
    end

    it "reports healthy when Redis is available" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      pool = Session::ConnectionPool.new(config)

      pool.healthy?.should be_true

      pool.shutdown
    end

    it "shuts down gracefully" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      pool = Session::ConnectionPool.new(config)

      pool.shutdown
      # After shutdown the channel is closed; healthy? should return false
      pool.healthy?.should be_false
    end
  end

  describe Session::PooledRedisStore do
    it "stores and retrieves sessions" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      store = Session::PooledRedisStore(UserSession).new(config)

      session = Session::SessionId(UserSession).new
      key = session.session_id

      (store[key] = session).should eq session
      store[key].session_id.should eq session.session_id
      store[key]?.should_not be_nil

      store.shutdown
    end

    it "returns nil for missing session via []?" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      store = Session::PooledRedisStore(UserSession).new(config)

      store["nonexistent"]?.should be_nil

      store.shutdown
    end

    it "raises SessionNotFoundException for missing session via []" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      store = Session::PooledRedisStore(UserSession).new(config)

      expect_raises(Session::SessionNotFoundException) do
        store["nonexistent"]
      end

      store.shutdown
    end

    it "deletes sessions" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      store = Session::PooledRedisStore(UserSession).new(config)

      session = Session::SessionId(UserSession).new
      key = session.session_id

      store[key] = session
      store.delete(key)
      store[key]?.should be_nil

      store.shutdown
    end

    it "reports size" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      store = Session::PooledRedisStore(UserSession).new(config)

      store.clear
      store.size.should eq 0

      session = Session::SessionId(UserSession).new
      store[session.session_id] = session
      store.size.should eq 1

      store.clear
      store.shutdown
    end

    it "clears all sessions" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      store = Session::PooledRedisStore(UserSession).new(config)

      session = Session::SessionId(UserSession).new
      store[session.session_id] = session
      store.size.should be > 0

      store.clear
      store.size.should eq 0

      store.shutdown
    end

    it "delegates healthy? to pool" do
      config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
      store = Session::PooledRedisStore(UserSession).new(config)

      store.healthy?.should be_true

      store.shutdown
    end

    describe "QueryableStore" do
      it "iterates sessions with each_session" do
        config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
        store = Session::PooledRedisStore(UserSession).new(config)
        store.clear

        s1 = Session::SessionId(UserSession).new
        s2 = Session::SessionId(UserSession).new
        store[s1.session_id] = s1
        store[s2.session_id] = s2

        ids = [] of String
        store.each_session { |s| ids << s.session_id }
        ids.size.should eq 2

        store.clear
        store.shutdown
      end

      it "returns all session ids" do
        config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
        store = Session::PooledRedisStore(UserSession).new(config)
        store.clear

        s1 = Session::SessionId(UserSession).new
        store[s1.session_id] = s1

        ids = store.all_session_ids
        ids.should contain(s1.session_id)

        store.clear
        store.shutdown
      end

      it "bulk deletes sessions matching predicate" do
        config = Session::ConnectionPoolConfig.new(size: 2, redis_host: REDIS_HOST)
        store = Session::PooledRedisStore(UserSession).new(config)
        store.clear

        s1 = Session::SessionId(UserSession).new
        s1.data.username = "delete_me"
        s2 = Session::SessionId(UserSession).new
        s2.data.username = "keep_me"

        store[s1.session_id] = s1
        store[s2.session_id] = s2

        deleted = store.bulk_delete { |s| s.data.username == "delete_me" }
        deleted.should eq 1
        store[s1.session_id]?.should be_nil
        store[s2.session_id]?.should_not be_nil

        store.clear
        store.shutdown
      end
    end
  end
end
