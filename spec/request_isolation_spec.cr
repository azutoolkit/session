require "./spec_helper"

private class Probe
  include HTTP::Handler

  getter seen = [] of String
  property? yield_mid_request = false

  def call(context : HTTP::Server::Context)
    Fiber.yield if yield_mid_request?
    seen << Session.config.store.as(Session::MemoryStore(UserSession)).current_session.session_id
  end
end

private def request_with(session_id : String?) : HTTP::Server::Context
  request = HTTP::Request.new("GET", "/")
  if session_id
    request.cookies << HTTP::Cookie.new(name: Session.config.session_key, value: session_id)
  end
  HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
end

describe "request isolation" do
  it "gives a visitor without a cookie a session of their own, not the previous visitor's" do
    reset_config
    store = Session::MemoryStore(UserSession).new
    Session.config.store = store
    owner = UserSession.new
    owner.username = "alice"
    store[owner.session_id] = owner

    handler = Session::SessionHandler(UserSession).new(store)
    handler.next = Probe.new

    handler.call(request_with(owner.session_id))
    anonymous = request_with(nil)
    handler.call(anonymous)

    cookie = anonymous.response.cookies[Session.config.session_key]?
    cookie.should_not be_nil
    cookie.try(&.value).should_not eq owner.session_id
  end

  it "keeps concurrent requests on their own sessions" do
    reset_config
    store = Session::MemoryStore(UserSession).new
    Session.config.store = store
    alice = UserSession.new
    bob = UserSession.new
    store[alice.session_id] = alice
    store[bob.session_id] = bob

    probe = Probe.new
    probe.yield_mid_request = true
    handler = Session::SessionHandler(UserSession).new(store)
    handler.next = probe

    done = Channel(Nil).new
    [alice, bob].each do |owner|
      spawn do
        handler.call(request_with(owner.session_id))
        done.send(nil)
      end
    end
    2.times { done.receive }

    probe.seen.sort.should eq [alice.session_id, bob.session_id].sort
  end

  it "releases the request's session when the request ends, even when it raises" do
    reset_config
    store = Session::MemoryStore(UserSession).new
    Session.config.store = store

    handler = Session::SessionHandler(UserSession).new(store)
    handler.next = ->(_context : HTTP::Server::Context) do
      store.current_session
      raise "boom"
    end

    expect_raises(Exception, "boom") { handler.call(request_with(nil)) }
    store.@current_sessions.should be_empty
  end

  it "does not keep sessions of fibers that have finished" do
    reset_config
    store = Session::MemoryStore(UserSession).new

    done = Channel(Nil).new
    50.times { spawn { store.current_session; done.send(nil) } }
    50.times { done.receive }
    Fiber.yield

    store.current_session
    store.@current_sessions.size.should be < 5
  end
end
