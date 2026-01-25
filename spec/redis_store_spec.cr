require "./spec_helper"

if REDIS_AVAILABLE
  describe Session::RedisStore do
    session = Session::SessionId(UserSession).new
    redis_store = Session::RedisStore(UserSession).new redis_client
    key = session.session_id

    it "persists sessions in redis" do
      (redis_store[key] = session).should eq session
    end

    it "gets session by id" do
      redis_store[key].should eq session
      redis_store[key]?.should eq session
    end

    it "returns nil for invalid session id" do
      redis_store["invalid"]?.should be_nil
    end

    it "deletes session by id" do
      redis_store.delete key
      redis_store[key]?.should be_nil
    end

    it "returns the total number of active sessions" do
      redis_store.clear
      redis_store.size.should eq 0
      redis_store[key] = session
      redis_store.size.should eq 1

      expired = Session::SessionId(UserSession).new
      redis_store[key] = expired
      redis_store.size.should eq 1
    end
  end
end
