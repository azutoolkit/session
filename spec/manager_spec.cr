require "./spec_helper"

describe Session::Manager do
  user_session = UserSession.new("dark-rider")
  redis_store = Session::RedisStore(UserSession).new Redis.new

  managers = {
    memory: Session::Manager(UserSession).new,
    redis:  Session::Manager(UserSession).new(store: redis_store),
  }

  stores = {
    memory: "Session::MemoryStore(UserSession)",
    redis:  "Session::RedisStore(UserSession)",
  }

  managers.each do |storage, manager|
    it "is a Session Provider" do
      manager.should be_a Session::Provider
      manager.storage.should eq stores[storage]
    end

    it "create a new session" do
      manager.create user_session

      manager.current_session.should be_a Session::SessionId(UserSession)
    end

    it "checks if session is valid" do
      manager.valid?.should be_true
    end

    it "returns the current session id" do
      manager.session_id.should be_a String
    end

    it "gets session data properties" do
      manager.username.should eq "dark-rider"
    end

    it "loads session from valid session cookie" do
      value = Session::SessionId(UserSession).new(manager.timeout)

      cookie = HTTP::Cookie.new(
        name: manager.session_key,
        value: manager.session_id,
        expires: manager.timeout.from_now,
        secure: true,
        http_only: true,
        creation_time: Time.local,
      )

      manager.load_from(cookie).should eq manager.current_session
    end

    it "creates a session cookie from current session" do
      cookie = manager.cookie
      cookie.name.should eq manager.session_key
      cookie.value.should eq manager.session_id
    end

    it "deletes the current session" do
      sid = manager.session_id
      manager.delete

      manager.current_session.should be_nil
      manager[sid]?.should be_nil
    end
  end
end
