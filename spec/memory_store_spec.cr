require "./spec_helper"

def prefixed(key)
  "_session:#{key}"
end

describe Session::MemoryStore do
  session = Session::SessionId(UserSession).new 1.hour
  memory_store = Session::MemoryStore(UserSession).new
  key = prefixed(session.session_id)

  it "persists sessions in memory" do
    memory_store.set(key, session, 1.hour).should eq session
  end

  it "gets session by id" do
    memory_store[key].should eq session
    memory_store[key]?.should eq session
  end

  it "returns nil for invalid session id" do
    memory_store["invalid"]?.should be_nil
  end

  it "deletes session by id" do
    memory_store.delete key
    memory_store[key]?.should be_nil
  end

  it "returns the total number of active sessions" do
    memory_store.size.should eq 0
    memory_store.set key, session, 1.hour
    memory_store.size.should eq 1

    expired = Session::SessionId(UserSession).new 1.hour
    memory_store.set key, expired, 1.hour
    memory_store.size.should eq 1
  end
end
