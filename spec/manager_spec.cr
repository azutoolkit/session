require "./spec_helper"

module App
  class_getter session = Session::Manager(UserSession).new
end

describe Session::Manager do
  user_session = UserSession.new("dark-rider")
  manager = Session::Manager(UserSession).new

  it "returns a session manager" do
    App.session.should be_a Session::Manager(UserSession)
  end

  it "create a new session" do
    manager.create user_session

    manager.current_session.should be_a Session::SessionId(UserSession)
  end

  it "returns the current session id" do
    manager.session_id.should be_a String
  end

  it "gets session data properties" do
    manager.username.should eq "dark-rider"
  end

  it "reads session from valid session cookie" do
    value = Session::SessionId(UserSession).new(manager.timeout)

    cookie = HTTP::Cookie.new(
      name: manager.session_key,
      value: manager.session_id,
      expires: manager.timeout.from_now,
      secure: true,
      http_only: true,
      creation_time: Time.local,
    )

    manager.load_from_cookie(cookie).should eq manager.current_session
  end

  it "reads session from valid session cookie" do
    value = Session::SessionId(UserSession).new(manager.timeout)

    cookie = HTTP::Cookie.new(
      name: manager.session_key,
      value: manager.session_id,
      expires: manager.timeout.from_now,
      secure: true,
      http_only: true,
      creation_time: Time.local,
    )

    manager.load_from_cookie(cookie).should eq manager.current_session
  end

  it "creates a session cookie from current session" do
    cookie = manager.cookie

    cookie.name.should eq manager.session_key
    cookie.value.should eq manager.session_id
  end
end
