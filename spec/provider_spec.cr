require "./spec_helper"

describe Session::Provider do
  # Define providers without Redis (Redis tests are conditional)
  providers_without_redis = {
    cookie: Session::CookieStore(UserSession).provider,
    memory: Session::MemoryStore(UserSession).provider,
  }

  stores = {
    cookie: "Session::CookieStore(UserSession)",
    memory: "Session::MemoryStore(UserSession)",
    redis:  "Session::RedisStore(UserSession)",
  }

  providers_without_redis.each do |storage, provider|
    it "is a Session Provider" do
      provider.should be_a Session::Provider
      provider.storage.should eq stores[storage]
    end

    it "creates a new session for #{stores[storage]}" do
      provider.create
      provider.current_session.should be_a Session::SessionId(UserSession)
    end

    it "checks if session is valid for #{stores[storage]}" do
      provider.valid?.should be_true
    end

    it "returns the current session id for #{stores[storage]}" do
      provider.session_id.should be_a String
    end

    it "gets session data properties for #{stores[storage]}" do
      provider.data.username = "dark-rider"
      provider.data.username.should eq "dark-rider"
    end

    it "loads session from valid session cookie for #{stores[storage]}" do
      cookies = HTTP::Cookies.new
      cookie = provider.create_session_cookie("localhost")
      cookies << cookie
      provider.set_cookies cookies, "localhost"

      provider.load_from(cookies)

      provider[cookie.value]?.should_not be_nil
    end

    it "creates a session cookie from current session for #{stores[storage]}" do
      cookie = provider.create_session_cookie("localhost")

      cookie.name.should eq provider.session_key
      cookie.value.should eq provider.session_id
    end

    it "deletes the current session for #{stores[storage]}" do
      cookies = HTTP::Cookies.new
      provider.set_cookies cookies

      sid = provider.session_id

      provider.delete

      provider.session_id.should_not eq(sid)
    end
  end

  describe "flash messages" do
    it "provides access to flash" do
      provider = Session::MemoryStore(UserSession).provider
      provider.flash.should be_a Session::Flash
    end

    it "rotates flash on load" do
      provider = Session::MemoryStore(UserSession).provider
      provider.flash["notice"] = "Hello"

      cookies = HTTP::Cookies.new
      provider.load_from(cookies)

      provider.flash.now["notice"].should eq "Hello"
      provider.flash.next.empty?.should be_true
    end
  end

  describe "session regeneration" do
    it "regenerates session ID" do
      provider = Session::MemoryStore(UserSession).provider
      provider.create
      old_id = provider.session_id
      provider.data.username = "keep-this"

      provider.regenerate_id

      provider.session_id.should_not eq old_id
      provider.data.username.should eq "keep-this"
    end
  end

  describe "sliding expiration" do
    it "touches session on load when enabled" do
      Session.config.sliding_expiration = true
      Session.config.timeout = 1.hour

      provider = Session::MemoryStore(UserSession).provider
      provider.create

      original_expires = provider.current_session.expires_at
      sleep 10.milliseconds

      cookies = HTTP::Cookies.new
      cookies << provider.create_session_cookie("localhost")
      provider.set_cookies cookies

      provider.load_from(cookies)

      # Expiry should have been extended
      provider.current_session.expires_at.should be >= original_expires
    end
  end
end

# Redis provider tests (only run if Redis is available)
if REDIS_AVAILABLE
  describe "Session::Provider with Redis" do
    it "works with RedisStore" do
      provider = Session::RedisStore(UserSession).provider(client: redis_client)
      provider.should be_a Session::Provider
      provider.storage.should eq "Session::RedisStore(UserSession)"
    end
  end
end
