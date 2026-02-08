require "./spec_helper"

module App
  class_getter session = Session::MemoryStore(UserSession).new
end

describe Session do
  it "returns a session manager" do
    App.session.should be_a Session::Store(UserSession)
  end
end
