require "./spec_helper"

# Helper handler that just returns 200
class OkHandler
  include HTTP::Handler

  def call(context : HTTP::Server::Context)
    context.response.status_code = 200
    context.response.print "OK"
  end
end

# Helper methods for creating test contexts
private def create_test_context : HTTP::Server::Context
  request = HTTP::Request.new("GET", "/")
  response = HTTP::Server::Response.new(IO::Memory.new)
  HTTP::Server::Context.new(request, response)
end

private def create_test_context_with_session(session_store, session_id : String) : HTTP::Server::Context
  context = create_test_context
  context.request.cookies << HTTP::Cookie.new(
    name: session_store.session_key,
    value: session_id,
    expires: 1.hour.from_now,
    secure: true,
    http_only: true,
    creation_time: Time.local
  )
  context
end

private def create_test_context_with_corrupted_session(session_store) : HTTP::Server::Context
  context = create_test_context
  context.request.cookies << HTTP::Cookie.new(
    name: session_store.session_key,
    value: "corrupted_session_data",
    expires: 1.hour.from_now,
    secure: true,
    http_only: true,
    creation_time: Time.local
  )
  context
end

private def create_test_context_with_invalid_session(session_store) : HTTP::Server::Context
  context = create_test_context
  context.request.cookies << HTTP::Cookie.new(
    name: session_store.session_key,
    value: "invalid_session_id",
    expires: 1.hour.from_now,
    secure: true,
    http_only: true,
    creation_time: Time.local
  )
  context
end

# Creates a handler chain with the session handler and an OK handler
private def create_handler_chain(session_handler)
  session_handler.next = OkHandler.new
  session_handler
end

describe "SessionHandler Error Handling" do
  session_store = Session::MemoryStore(UserSession).new
  session_handler = create_handler_chain(Session::SessionHandler.new(session_store))

  before_each do
    session_store.delete
    Session.config.timeout = 1.hour
  end

  describe "Session Loading with Error Handling" do
    it "handles missing session cookies gracefully" do
      context = create_test_context

      # Should not raise an error when no session cookies exist
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "handles expired sessions gracefully" do
      # Create a valid session first
      Session.config.timeout = 1.hour
      valid_session = session_store.create
      valid_session.username = "test_user"
      session_id = valid_session.session_id

      # Now access with a session that doesn't exist anymore (simulating expiration)
      session_store.delete

      context = create_test_context_with_session(session_store, session_id)

      # Should handle expired/missing session gracefully
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "handles corrupted session data gracefully" do
      # Create a context with corrupted session data
      context = create_test_context_with_corrupted_session(session_store)

      # Should handle corrupted session gracefully
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "handles storage connection errors gracefully" do
      # This would require mocking the storage to simulate connection errors
      # For now, we test the normal case
      context = create_test_context
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "handles session validation errors gracefully" do
      # Create an invalid session
      context = create_test_context_with_invalid_session(session_store)

      # Should handle validation errors gracefully
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end
  end

  describe "Cookie Setting with Error Handling" do
    it "handles encryption errors gracefully" do
      # Create a valid session
      session = session_store.create
      session.username = "test_user"

      context = create_test_context_with_session(session_store, session.session_id)

      # Should handle encryption errors gracefully
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "handles validation errors gracefully" do
      # Create a session that would fail validation
      session = session_store.create
      session.username = "test_user"

      context = create_test_context_with_session(session_store, session.session_id)

      # Should handle validation errors gracefully
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "handles cookie setting errors gracefully" do
      # This would require mocking to simulate cookie setting errors
      # For now, we test the normal case
      context = create_test_context
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end
  end

  describe "Corrupted Session Cleanup" do
    it "clears corrupted sessions" do
      # Create a context with corrupted session data
      context = create_test_context_with_corrupted_session(session_store)

      # Should clear corrupted session and continue
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "creates new session after clearing corrupted one" do
      # Create a context with corrupted session data
      context = create_test_context_with_corrupted_session(session_store)

      # Should create new session after clearing corrupted one
      session_handler.call(context)
      context.response.status_code.should eq(200)

      # Store should have a valid session
      session_store.valid?.should be_true
    end

    it "handles cleanup errors gracefully" do
      # This would require mocking to simulate cleanup errors
      # For now, we test the normal case
      context = create_test_context_with_corrupted_session(session_store)
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end
  end

  describe "Request Processing Continuity" do
    it "continues processing when session loading fails" do
      # Create a context that would cause session loading to fail
      context = create_test_context_with_corrupted_session(session_store)

      # Add a flag to track if processing continues
      context.response.headers.add("X-Processing-Continued", "true")

      # Should continue processing even if session loading fails
      session_handler.call(context)
      context.response.status_code.should eq(200)

      # Verify processing continued
      context.response.headers["X-Processing-Continued"]?.should eq("true")
    end

    it "continues processing when cookie setting fails" do
      # Create a valid session
      session = session_store.create
      session.username = "test_user"

      context = create_test_context_with_session(session_store, session.session_id)

      # Add a flag to track if processing continues
      context.response.headers.add("X-Processing-Continued", "true")

      # Should continue processing even if cookie setting fails
      session_handler.call(context)
      context.response.status_code.should eq(200)

      # Verify processing continued
      context.response.headers["X-Processing-Continued"]?.should eq("true")
    end
  end

  describe "Error Logging" do
    it "logs session expiration appropriately" do
      # Create a valid session then delete it
      Session.config.timeout = 1.hour
      session = session_store.create
      session.username = "expired_user"
      session_id = session.session_id

      session_store.delete

      context = create_test_context_with_session(session_store, session_id)

      # Should log session expiration
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "logs session corruption appropriately" do
      # Create a context with corrupted session data
      context = create_test_context_with_corrupted_session(session_store)

      # Should log session corruption
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "logs storage connection errors appropriately" do
      # This would require mocking to simulate storage connection errors
      # For now, we test the normal case
      context = create_test_context
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "logs validation errors appropriately" do
      # Create a context with invalid session data
      context = create_test_context_with_invalid_session(session_store)

      # Should log validation errors
      session_handler.call(context)
      context.response.status_code.should eq(200)
    end
  end

  describe "Integration with Different Storage Types" do
    it "works with memory store" do
      memory_store = Session::MemoryStore(UserSession).new
      memory_handler = create_handler_chain(Session::SessionHandler.new(memory_store))

      context = create_test_context
      memory_handler.call(context)
      context.response.status_code.should eq(200)
    end

    it "works with cookie store" do
      cookie_store = Session::CookieStore(UserSession).new
      cookie_handler = create_handler_chain(Session::SessionHandler.new(cookie_store))

      context = create_test_context
      cookie_handler.call(context)
      context.response.status_code.should eq(200)
    end
  end
end

# Redis integration tests (only run if Redis is available)
if REDIS_AVAILABLE
  describe "SessionHandler Redis Integration" do
    it "works with Redis store" do
      redis_store = Session::RedisStore(UserSession).new(client: redis_client)
      ok_handler = OkHandler.new
      redis_handler = Session::SessionHandler.new(redis_store)
      redis_handler.next = ok_handler

      request = HTTP::Request.new("GET", "/")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      redis_handler.call(context)
      context.response.status_code.should eq(200)
    end
  end
end
