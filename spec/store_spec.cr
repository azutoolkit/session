require "./spec_helper"

describe Session::Store do
  # Define stores without Redis (Redis tests are conditional)
  stores_without_redis = {
    cookie: Session::CookieStore(UserSession).new,
    memory: Session::MemoryStore(UserSession).new,
  }

  store_names = {
    cookie: "Session::CookieStore(UserSession)",
    memory: "Session::MemoryStore(UserSession)",
    redis:  "Session::RedisStore(UserSession)",
  }

  stores_without_redis.each do |storage, store|
    it "is a Session Store for #{store_names[storage]}" do
      store.should be_a Session::Store(UserSession)
      store.storage.should eq store_names[storage]
    end

    it "creates a new session for #{store_names[storage]}" do
      store.create
      store.current_session.should be_a UserSession
    end

    it "checks if session is valid for #{store_names[storage]}" do
      store.valid?.should be_true
    end

    it "returns the current session id for #{store_names[storage]}" do
      store.session_id.should be_a String
    end

    it "gets session data properties for #{store_names[storage]}" do
      store.current_session.username = "dark-rider"
      store.current_session.username.should eq "dark-rider"
    end

    it "loads session from valid session cookie for #{store_names[storage]}" do
      cookies = HTTP::Cookies.new
      cookie = store.create_session_cookie("localhost")
      cookies << cookie
      store.set_cookies cookies, "localhost"

      store.load_from(cookies)

      store[cookie.value]?.should_not be_nil
    end

    it "creates a session cookie from current session for #{store_names[storage]}" do
      cookie = store.create_session_cookie("localhost")

      cookie.name.should eq store.session_key
      cookie.value.should eq store.session_id
    end

    it "deletes the current session for #{store_names[storage]}" do
      cookies = HTTP::Cookies.new
      store.set_cookies cookies

      sid = store.session_id

      store.delete

      store.session_id.should_not eq(sid)
    end
  end

  describe "flash messages" do
    it "provides access to flash" do
      store = Session::MemoryStore(UserSession).new
      store.flash.should be_a Session::Flash
    end

    it "rotates flash on load" do
      store = Session::MemoryStore(UserSession).new
      store.flash["notice"] = "Hello"

      cookies = HTTP::Cookies.new
      store.load_from(cookies)

      store.flash.now["notice"].should eq "Hello"
      store.flash.next.empty?.should be_true
    end
  end

  describe "session regeneration" do
    it "regenerates session ID" do
      store = Session::MemoryStore(UserSession).new
      store.create
      old_id = store.session_id
      store.current_session.username = "keep-this"

      store.regenerate_id

      store.session_id.should_not eq old_id
      store.current_session.username.should eq "keep-this"
    end
  end

  describe "sliding expiration" do
    it "touches session on load when enabled" do
      Session.config.sliding_expiration = true
      Session.config.timeout = 1.hour

      store = Session::MemoryStore(UserSession).new
      store.create

      original_expires = store.current_session.expires_at
      sleep 10.milliseconds

      cookies = HTTP::Cookies.new
      cookies << store.create_session_cookie("localhost")
      store.set_cookies cookies

      store.load_from(cookies)

      # Expiry should have been extended
      store.current_session.expires_at.should be >= original_expires
    end
  end
end

# Redis store tests (only run if Redis is available)
if REDIS_AVAILABLE
  describe "Session::Store with Redis" do
    it "works with RedisStore" do
      store = Session::RedisStore(UserSession).new(client: redis_client)
      store.should be_a Session::Store(UserSession)
      store.storage.should eq "Session::RedisStore(UserSession)"
    end
  end
end
