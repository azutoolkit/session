require "./spec_helper"

module App
  class_getter session = Session::MemoryStore(UserSession).provider
end

describe Session do
  it "returns a session manager" do
    App.session.should be_a Session::Manager(UserSession)
  end
end
