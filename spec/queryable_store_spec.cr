require "./spec_helper"

describe Session::QueryableStore do
  describe "MemoryStore implementation" do
    it "implements each_session" do
      store = Session::MemoryStore(UserSession).new
      session1 = Session::SessionId(UserSession).new
      session2 = Session::SessionId(UserSession).new

      store[session1.session_id] = session1
      store[session2.session_id] = session2

      sessions = [] of Session::SessionId(UserSession)
      store.each_session { |s| sessions << s }

      sessions.size.should eq 2
    end

    it "finds sessions by predicate" do
      store = Session::MemoryStore(UserSession).new

      session1 = Session::SessionId(UserSession).new
      session1.data.username = "user1"

      session2 = Session::SessionId(UserSession).new
      session2.data.username = "user2"

      session3 = Session::SessionId(UserSession).new
      session3.data.username = "user1"

      store[session1.session_id] = session1
      store[session2.session_id] = session2
      store[session3.session_id] = session3

      results = store.find_by { |s| s.data.username == "user1" }
      results.size.should eq 2
    end

    it "finds first matching session" do
      store = Session::MemoryStore(UserSession).new

      session1 = Session::SessionId(UserSession).new
      session1.data.username = "target"

      session2 = Session::SessionId(UserSession).new
      session2.data.username = "other"

      store[session1.session_id] = session1
      store[session2.session_id] = session2

      result = store.find_first { |s| s.data.username == "target" }
      result.should_not be_nil
      result.try(&.data.username).should eq "target"
    end

    it "returns nil when no match found" do
      store = Session::MemoryStore(UserSession).new
      session = Session::SessionId(UserSession).new
      store[session.session_id] = session

      result = store.find_first { |s| s.data.username == "nonexistent" }
      result.should be_nil
    end

    it "counts sessions by predicate" do
      store = Session::MemoryStore(UserSession).new

      3.times do |i|
        session = Session::SessionId(UserSession).new
        session.data.authenticated = (i < 2)
        store[session.session_id] = session
      end

      count = store.count_by(&.data.authenticated?)
      count.should eq 2
    end

    it "bulk deletes sessions by predicate" do
      store = Session::MemoryStore(UserSession).new

      session1 = Session::SessionId(UserSession).new
      session1.data.username = "delete_me"

      session2 = Session::SessionId(UserSession).new
      session2.data.username = "keep_me"

      session3 = Session::SessionId(UserSession).new
      session3.data.username = "delete_me"

      store[session1.session_id] = session1
      store[session2.session_id] = session2
      store[session3.session_id] = session3

      deleted = store.bulk_delete { |s| s.data.username == "delete_me" }

      deleted.should eq 2
      store.size.should eq 1
      store.find_first { |s| s.data.username == "keep_me" }.should_not be_nil
    end

    it "returns all session IDs" do
      store = Session::MemoryStore(UserSession).new
      store.clear

      session1 = Session::SessionId(UserSession).new
      session2 = Session::SessionId(UserSession).new

      store[session1.session_id] = session1
      store[session2.session_id] = session2

      ids = store.all_session_ids
      ids.size.should eq 2
      ids.should contain(session1.session_id)
      ids.should contain(session2.session_id)
    end

    it "excludes expired sessions from iteration" do
      store = Session::MemoryStore(UserSession).new
      store.clear

      # Create valid session
      Session.config.timeout = 1.hour
      valid_session = Session::SessionId(UserSession).new
      store.sessions[valid_session.session_id] = valid_session

      # Create expired session (directly in hash to bypass validation)
      Session.config.timeout = -1.hour
      expired_session = Session::SessionId(UserSession).new
      store.sessions[expired_session.session_id] = expired_session

      Session.config.timeout = 1.hour # Reset

      sessions = [] of Session::SessionId(UserSession)
      store.each_session { |s| sessions << s }

      sessions.size.should eq 1
      sessions.first.session_id.should eq valid_session.session_id
    end
  end
end
