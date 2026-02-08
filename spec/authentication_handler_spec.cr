require "./spec_helper"

# Helper handler that records it was called
class RecordingHandler
  include HTTP::Handler

  getter called : Bool = false

  def call(context : HTTP::Server::Context)
    @called = true
    context.response.status_code = 200
    context.response.print "OK"
  end
end

describe Session::AuthenticationHandler do
  signin_path = "/signin"
  whitelist = /\A\/(public|health)/

  describe "#call" do
    it "passes through when session is authenticated" do
      store = Session::MemoryStore(UserSession).new
      session = store.create
      session.authenticated = true

      recorder = RecordingHandler.new
      handler = Session::AuthenticationHandler.new(store, signin_path, whitelist)
      handler.next = recorder

      request = HTTP::Request.new("GET", "/dashboard")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      recorder.called.should be_true
      context.response.status_code.should eq(200)
    end

    it "redirects to signin when session is not authenticated" do
      store = Session::MemoryStore(UserSession).new
      session = store.create
      session.authenticated = false

      recorder = RecordingHandler.new
      handler = Session::AuthenticationHandler.new(store, signin_path, whitelist)
      handler.next = recorder

      request = HTTP::Request.new("GET", "/dashboard")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      recorder.called.should be_false
      context.response.status_code.should eq(302)
      context.response.headers["Location"].should eq("/signin?redirect_to=/dashboard")
    end

    it "includes redirect_to with the original resource path" do
      store = Session::MemoryStore(UserSession).new
      session = store.create
      session.authenticated = false

      handler = Session::AuthenticationHandler.new(store, signin_path, whitelist)
      handler.next = RecordingHandler.new

      request = HTTP::Request.new("GET", "/admin/settings?tab=security")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      context.response.status_code.should eq(302)
      context.response.headers["Location"].should eq("/signin?redirect_to=/admin/settings?tab=security")
    end

    it "passes through whitelisted paths even when not authenticated" do
      store = Session::MemoryStore(UserSession).new
      session = store.create
      session.authenticated = false

      recorder = RecordingHandler.new
      handler = Session::AuthenticationHandler.new(store, signin_path, whitelist)
      handler.next = recorder

      request = HTTP::Request.new("GET", "/public/assets/style.css")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      recorder.called.should be_true
      context.response.status_code.should eq(200)
    end

    it "passes through health endpoint when not authenticated" do
      store = Session::MemoryStore(UserSession).new
      session = store.create
      session.authenticated = false

      recorder = RecordingHandler.new
      handler = Session::AuthenticationHandler.new(store, signin_path, whitelist)
      handler.next = recorder

      request = HTTP::Request.new("GET", "/health")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      recorder.called.should be_true
      context.response.status_code.should eq(200)
    end
  end

  describe "#current_session" do
    it "delegates to the store" do
      store = Session::MemoryStore(UserSession).new
      session = store.create
      session.username = "test_user"

      handler = Session::AuthenticationHandler.new(store, signin_path, whitelist)

      handler.current_session.session_id.should eq(session.session_id)
      handler.current_session.username.should eq("test_user")
    end
  end
end
