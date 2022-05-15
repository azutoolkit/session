require "./spec_helper"

def prefixed(key)
  "_session:#{key}"
end

describe Session::RedisStore do
  session = Session::SessionId(UserSession).new 1.hour
  client = Redis.new
  redis_store = Session::RedisStore(UserSession).new client
  key = prefixed(session.session_id)

  it "persists sessions in redis" do
    redis_store.set(key, session, 1.hour).should eq session
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
    redis_store.size.should eq 0
  end
end
