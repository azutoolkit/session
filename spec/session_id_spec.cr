require "./spec_helper"

describe Session::SessionId do
  it "valid session" do
    session_id = Session::SessionId(UserSession).new

    session_id.expired?.should be_false
    session_id.valid?.should be_true
  end

  it "invalid session" do
    Session.config.timeout = -1.hour
    session_id = Session::SessionId(UserSession).new
    session_id.expired?.should be_true
    session_id.valid?.should be_false

    Session.config.timeout = 1.hour
  end
end
