require "./spec_helper"

describe Session::Provider do
  providers = {
    cookie: Session::CookieStore(UserSession).provider,
    memory: Session::MemoryStore(UserSession).provider,
    redis:  Session::RedisStore(UserSession).provider(client: REDIS_CLIENT),
  }

  stores = {
    cookie: "Session::CookieStore(UserSession)",
    memory: "Session::MemoryStore(UserSession)",
    redis:  "Session::RedisStore(UserSession)",
  }

  providers.each do |storage, provider|
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
      provider.set_cookies cookies

      provider.load_from(cookies).should eq provider.current_session
    end

    it "creates a session cookie from current session for #{stores[storage]}" do
      cookie = provider.cookie("localhost")

      cookie.name.should eq provider.session_key
      cookie.value.should eq provider.session_id
    end

    it "deletes the current session for #{stores[storage]}" do
      cookies = HTTP::Cookies.new
      provider.set_cookies cookies

      sid = provider.session_id

      provider.delete

      provider[sid]?.should be_nil
    end
  end
end
