require "./spec_helper"

describe Session::QueryableStore do
  describe "MemoryStore implementation" do
    it "implements each_session" do
      store = Session::MemoryStore(UserSession).new
      session1 = UserSession.new
      session2 = UserSession.new

      store[session1.session_id] = session1
      store[session2.session_id] = session2

      sessions = [] of UserSession
      store.each_session { |s| sessions << s }

      sessions.size.should eq 2
    end

    it "finds sessions by predicate" do
      store = Session::MemoryStore(UserSession).new

      session1 = UserSession.new
      session1.username = "user1"

      session2 = UserSession.new
      session2.username = "user2"

      session3 = UserSession.new
      session3.username = "user1"

      store[session1.session_id] = session1
      store[session2.session_id] = session2
      store[session3.session_id] = session3

      results = store.find_by { |s| s.username == "user1" }
      results.size.should eq 2
    end

    it "finds first matching session" do
      store = Session::MemoryStore(UserSession).new

      session1 = UserSession.new
      session1.username = "target"

      session2 = UserSession.new
      session2.username = "other"

      store[session1.session_id] = session1
      store[session2.session_id] = session2

      result = store.find_first { |s| s.username == "target" }
      result.should_not be_nil
      result.try(&.username).should eq "target"
    end

    it "returns nil when no match found" do
      store = Session::MemoryStore(UserSession).new
      session = UserSession.new
      store[session.session_id] = session

      result = store.find_first { |s| s.username == "nonexistent" }
      result.should be_nil
    end

    it "counts sessions by predicate" do
      store = Session::MemoryStore(UserSession).new

      3.times do |i|
        session = UserSession.new
        session.authenticated = (i < 2)
        store[session.session_id] = session
      end

      count = store.count_by(&.authenticated?)
      count.should eq 2
    end

    it "bulk deletes sessions by predicate" do
      store = Session::MemoryStore(UserSession).new

      session1 = UserSession.new
      session1.username = "delete_me"

      session2 = UserSession.new
      session2.username = "keep_me"

      session3 = UserSession.new
      session3.username = "delete_me"

      store[session1.session_id] = session1
      store[session2.session_id] = session2
      store[session3.session_id] = session3

      deleted = store.bulk_delete { |s| s.username == "delete_me" }

      deleted.should eq 2
      store.size.should eq 1
      store.find_first { |s| s.username == "keep_me" }.should_not be_nil
    end

    it "returns all session IDs" do
      store = Session::MemoryStore(UserSession).new
      store.clear

      session1 = UserSession.new
      session2 = UserSession.new

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
      valid_session = UserSession.new
      store.sessions[valid_session.session_id] = valid_session

      # Create expired session (directly in hash to bypass validation)
      Session.config.timeout = -1.hour
      expired_session = UserSession.new
      store.sessions[expired_session.session_id] = expired_session

      Session.config.timeout = 1.hour # Reset

      sessions = [] of UserSession
      store.each_session { |s| sessions << s }

      sessions.size.should eq 1
      sessions.first.session_id.should eq valid_session.session_id
    end
  end
end
