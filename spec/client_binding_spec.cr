require "./spec_helper"

private class Seen
  include HTTP::Handler

  getter ids = [] of String

  def call(context : HTTP::Server::Context)
    ids << Session.config.store.as(Session::MemoryStore(UserSession)).current_session.session_id
  end
end

private def request_from(cookie : String?, ip : String = "10.0.0.1", user_agent : String = "agent-a", headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Server::Context
  headers["User-Agent"] = user_agent
  request = HTTP::Request.new("GET", "/", headers)
  request.remote_address = Socket::IPAddress.new(ip, 40000)
  request.cookies << HTTP::Cookie.new(name: Session.config.session_key, value: cookie) if cookie
  HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
end

private def with_handler(&)
  reset_config
  Session.config.bind_to_ip = true
  Session.config.bind_to_user_agent = true
  store = Session::MemoryStore(UserSession).new
  Session.config.store = store
  seen = Seen.new
  handler = Session::SessionHandler(UserSession).new(store)
  handler.next = seen
  yield handler, seen
ensure
  Session.config.bind_to_ip = false
  Session.config.bind_to_user_agent = false
  Session.config.trust_proxy_headers = false
end

# The session id the first request of a new visitor was given.
private def first_visit(handler, seen, **client) : String
  handler.call(request_from(nil, **client))
  seen.ids.last
end

describe "session binding in the handler" do
  it "keeps a session for the client it was first used from" do
    with_handler do |handler, seen|
      id = first_visit(handler, seen)

      handler.call(request_from(id))

      seen.ids.last.should eq id
    end
  end

  it "does not let another browser use the session" do
    with_handler do |handler, seen|
      id = first_visit(handler, seen)

      handler.call(request_from(id, user_agent: "agent-b"))

      seen.ids.last.should_not eq id
    end
  end

  it "does not let another address use the session" do
    with_handler do |handler, seen|
      id = first_visit(handler, seen)

      handler.call(request_from(id, ip: "203.0.113.9"))

      seen.ids.last.should_not eq id
    end
  end

  it "ignores X-Forwarded-For unless a trusted proxy is configured, since any client can send it" do
    with_handler do |handler, seen|
      id = first_visit(handler, seen)

      forged = HTTP::Headers{"X-Forwarded-For" => "10.0.0.1"}
      handler.call(request_from(id, ip: "203.0.113.9", headers: forged))

      seen.ids.last.should_not eq id
    end
  end

  it "believes X-Forwarded-For behind a trusted proxy" do
    with_handler do |handler, seen|
      Session.config.trust_proxy_headers = true
      id = first_visit(handler, seen, headers: HTTP::Headers{"X-Forwarded-For" => "198.51.100.7"})

      handler.call(request_from(id, ip: "172.16.0.1", headers: HTTP::Headers{"X-Forwarded-For" => "198.51.100.7"}))

      seen.ids.last.should eq id
    end
  end
end
