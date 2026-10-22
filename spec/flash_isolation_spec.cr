require "./spec_helper"

# Reads the flash of the request it serves, then optionally sets one for the next request.
private class FlashProbe
  include HTTP::Handler

  getter shown = [] of String?
  property next_message : String? = nil

  def initialize(@store : Session::MemoryStore(UserSession))
  end

  def call(context : HTTP::Server::Context)
    shown << @store.flash.now["notice"]?
    @store.flash.next["notice"] = next_message.not_nil! if next_message
  end
end

private def request_for(session_id : String) : HTTP::Server::Context
  request = HTTP::Request.new("GET", "/")
  request.cookies << HTTP::Cookie.new(name: Session.config.session_key, value: session_id)
  HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
end

describe "flash messages" do
  it "reach the session that set them, and nobody else's" do
    reset_config
    store = Session::MemoryStore(UserSession).new
    Session.config.store = store
    alice = UserSession.new
    bob = UserSession.new
    store[alice.session_id] = alice
    store[bob.session_id] = bob

    probe = FlashProbe.new(store)
    handler = Session::SessionHandler(UserSession).new(store)
    handler.next = probe

    probe.next_message = "Alice's private notice"
    handler.call(request_for(alice.session_id))
    probe.next_message = nil
    handler.call(request_for(bob.session_id))
    handler.call(request_for(alice.session_id))

    probe.shown.should eq [nil, nil, "Alice's private notice"]
  end

  it "lasts for exactly one request" do
    reset_config
    store = Session::MemoryStore(UserSession).new
    Session.config.store = store
    alice = UserSession.new
    store[alice.session_id] = alice

    probe = FlashProbe.new(store)
    handler = Session::SessionHandler(UserSession).new(store)
    handler.next = probe

    probe.next_message = "once"
    handler.call(request_for(alice.session_id))
    probe.next_message = nil
    2.times { handler.call(request_for(alice.session_id)) }

    probe.shown.should eq [nil, "once", nil]
  end

  it "is saved with the session, so a store that serializes it keeps it" do
    session = UserSession.new
    session.flash.next["notice"] = "saved"

    UserSession.from_json(session.to_json).flash.next["notice"].should eq "saved"
  end
end
