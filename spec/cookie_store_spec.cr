require "./spec_helper"

describe Session::CookieStore do
  describe "#[]=" do
    it "stores session in cookies" do
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new

      store[session.session_id] = session

      store[session.session_id]?.should_not be_nil
    end

    it "encrypts session data" do
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new

      store[session.session_id] = session

      # The cookie value should be encrypted, not plain JSON
      cookie = store.cookies[store.data_key]?
      cookie.should_not be_nil
      cookie.try(&.value).should_not contain("session_id")
    end
  end

  describe "#[]" do
    it "retrieves stored session" do
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new
      store[session.session_id] = session

      retrieved = store[session.session_id]
      retrieved.session_id.should eq session.session_id
    end

    it "raises SessionNotFoundException for missing session" do
      store = Session::CookieStore(UserSession).new

      expect_raises(Session::SessionNotFoundException) do
        store["nonexistent"]
      end
    end
  end

  describe "#[]?" do
    it "returns nil for missing session" do
      store = Session::CookieStore(UserSession).new
      store["nonexistent"]?.should be_nil
    end

    it "returns session when found" do
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new
      store[session.session_id] = session

      store[session.session_id]?.should_not be_nil
    end
  end

  describe "#delete" do
    it "removes session from cookies" do
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new
      store[session.session_id] = session

      store.delete(session.session_id)

      store[session.session_id]?.should be_nil
    end
  end

  describe "#size" do
    it "returns count of session cookies" do
      store = Session::CookieStore(UserSession).new
      store.size.should eq 0

      session = Session::SessionId(UserSession).new
      store[session.session_id] = session

      store.size.should eq 1
    end
  end

  describe "#clear" do
    it "removes all session cookies" do
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new
      store[session.session_id] = session

      store.clear
      store.size.should eq 0
    end
  end

  describe "cookie size validation" do
    it "raises CookieSizeExceededException for oversized data" do
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new

      # Create session with very large data
      session.data.username = "x" * 10000

      expect_raises(Session::CookieSizeExceededException) do
        store[session.session_id] = session
      end
    end

    it "stores normal-sized sessions" do
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new
      session.data.username = "normal_user"

      store[session.session_id] = session
      store[session.session_id]?.should_not be_nil
    end
  end

  describe "with compression" do
    it "compresses large session data" do
      # Save original values
      original_compress = Session.config.compress_data
      original_threshold = Session.config.compression_threshold

      Session.config.compress_data = true
      Session.config.compression_threshold = 100

      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new
      session.data.username = "test_" * 50 # Create data above threshold

      store[session.session_id] = session
      retrieved = store[session.session_id]

      retrieved.data.username.should eq session.data.username

      # Restore original values
      Session.config.compress_data = original_compress
      Session.config.compression_threshold = original_threshold
    end
  end

  describe "#create_data_cookie" do
    it "creates cookie with correct attributes" do
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new

      cookie = store.create_data_cookie(session, "example.com")

      cookie.name.should eq store.data_key
      cookie.secure.should be_true
      cookie.http_only.should be_true
      cookie.domain.should eq "example.com"
      cookie.path.should eq "/"
      cookie.samesite.should eq HTTP::Cookie::SameSite::Strict
    end

    it "raises for expired session" do
      Session.config.timeout = -1.hour
      store = Session::CookieStore(UserSession).new
      session = Session::SessionId(UserSession).new

      expect_raises(Session::SessionValidationException) do
        store.create_data_cookie(session)
      end
    end
  end
end

describe Session::CookieSizeExceededException do
  it "includes size information" do
    ex = Session::CookieSizeExceededException.new(5000, 4096)

    ex.actual_size.should eq 5000
    ex.max_size.should eq 4096
    ex.message.to_s.should contain("5000")
    ex.message.to_s.should contain("4096")
  end

  it "uses default max size" do
    ex = Session::CookieSizeExceededException.new(5000)
    ex.max_size.should eq Session::CookieSizeExceededException::MAX_COOKIE_SIZE
  end
end
