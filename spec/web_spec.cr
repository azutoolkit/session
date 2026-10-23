require "./spec_helper"
require "../src/azu"

Session::Web.use_store(Session::MemoryStore(UserSession))

# A store that keeps serialized copies, as Redis does: later changes to the live session object
# do not reach the store unless it is saved again.
class WebSpecSerializingStore < Session::MemoryStore(UserSession)
  def []=(key : String, session : UserSession) : UserSession
    super(key, UserSession.from_json(session.to_json))
    session
  end

  def tracked_sessions : Int32
    @mutex.synchronize { @current_sessions.size }
  end
end

# A tiny app behind the session handler, standing in for an Azu application.
class WebSpecApp
  include HTTP::Handler

  def initialize(@store : Session::Store(UserSession))
  end

  def call(context : HTTP::Server::Context)
    params = context.request.query_params
    case {context.request.method, context.request.path}
    when {"POST", "/login"}
      @store.authenticate { |session| session.username = params["name"] }
      @store.flash["notice"] = "Welcome back"
      context.response.print "ok"
    when {"POST", "/logout"}
      @store.delete
      context.response.print "ok"
    when {"GET", "/me"}
      context.response.print "#{@store.current_session.username}|#{@store.flash.now["notice"]?}"
    when {"GET", "/context"}
      context.response.print "#{context.session.username}|#{context.flash.now["notice"]?}"
    when {"GET", "/id"}
      context.response.print @store.current_session.session_id
    when {"GET", "/slow"}
      @store.current_session.username = params["name"]
      sleep 20.milliseconds
      context.response.print @store.current_session.username
    when {"GET", "/late"}
      @store.current_session.username = "before"
      context.response.print "ok"
      context.response.flush
      @store.current_session.username = "after"
      @store.flash["notice"] = "late flash"
    when {"POST", "/late-login"}
      context.response.print "ok"
      context.response.flush
      @store.authenticate { |session| session.username = params["name"] }
    when {"GET", "/spawned"}
      @store.current_session.username = "alice"
      id = @store.session_id
      done = Channel(Nil).new
      spawn do
        context.response.print id
        context.response.flush
        done.send(nil)
      end
      done.receive
    when {"GET", "/large"}
      @store.current_session.username = params["name"]
      context.response.print "x" * 200_000
    else
      context.response.status_code = 404
    end
  end
end

# Keeps the cookies a server sets and sends them back, as a browser does.
class WebSpecBrowser
  getter cookies = HTTP::Cookies.new

  def initialize(@address : Socket::IPAddress)
  end

  def request(method : String, path : String) : HTTP::Client::Response
    headers = HTTP::Headers.new
    cookies.add_request_headers(headers)
    HTTP::Client.exec(method, "http://#{@address}#{path}", headers).tap do |response|
      cookies.fill_from_server_headers(response.headers)
    end
  end

  def get(path : String) : String
    request("GET", path).body
  end

  def post(path : String) : String
    request("POST", path).body
  end
end

def with_web_server(store : Session::Store(UserSession), &)
  server = HTTP::Server.new([Session::SessionHandler.new(store), WebSpecApp.new(store)] of HTTP::Handler)
  address = server.bind_unused_port
  spawn { server.listen }
  Fiber.yield
  yield address
ensure
  server.try &.close
end

describe "Session over a real HTTP::Server" do
  describe "with a server-side store" do
    it "keeps a login across requests" do
      with_web_server(Session.session) do |address|
        browser = WebSpecBrowser.new(address)
        browser.get("/me").should eq "example|"

        browser.post("/login?name=alice")
        browser.get("/me").should start_with "alice|"
      end
    end

    it "exposes the session and flash of the request on the context" do
      with_web_server(Session.session) do |address|
        browser = WebSpecBrowser.new(address)
        browser.post("/login?name=alice")

        browser.get("/context").should eq "alice|Welcome back"
        browser.get("/context").should eq "alice|"
      end
    end

    it "shows a flash message exactly once" do
      with_web_server(Session.session) do |address|
        browser = WebSpecBrowser.new(address)
        browser.post("/login?name=alice")

        browser.get("/me").should eq "alice|Welcome back"
        browser.get("/me").should eq "alice|"
        browser.get("/me").should eq "alice|"
      end
    end

    it "keeps a flash message away from other visitors" do
      with_web_server(Session.session) do |address|
        alice = WebSpecBrowser.new(address)
        bob = WebSpecBrowser.new(address)
        alice.post("/login?name=alice")

        bob.get("/me").should eq "example|"
        alice.get("/me").should eq "alice|Welcome back"
      end
    end

    it "replaces the session id on login and rejects the old one" do
      with_web_server(Session.session) do |address|
        browser = WebSpecBrowser.new(address)
        before = browser.get("/id")
        planted = browser.cookies[Session.config.session_key].value
        planted.should eq before

        browser.post("/login?name=alice")
        browser.get("/id").should_not eq before

        attacker = WebSpecBrowser.new(address)
        attacker.cookies << HTTP::Cookie.new(Session.config.session_key, planted)
        attacker.get("/me").should eq "example|"
        attacker.get("/id").should_not eq before
      end
    end

    it "starts a new session on logout" do
      with_web_server(Session.session) do |address|
        browser = WebSpecBrowser.new(address)
        browser.post("/login?name=alice")
        browser.post("/logout")

        browser.get("/me").should eq "example|"
      end
    end

    it "ignores a session id it never issued" do
      with_web_server(Session.session) do |address|
        browser = WebSpecBrowser.new(address)
        browser.cookies << HTTP::Cookie.new(Session.config.session_key, "forged-id")

        browser.get("/id").should_not eq "forged-id"
        browser.get("/me").should eq "example|"
      end
    end

    it "does not share state between concurrent requests" do
      with_web_server(Session.session) do |address|
        names = (1..25).map { |index| "user#{index}" }
        results = Channel({String, String}).new

        names.each do |name|
          spawn do
            browser = WebSpecBrowser.new(address)
            results.send({name, browser.get("/slow?name=#{name}")})
          end
        end

        names.size.times do
          name, answer = results.receive
          answer.should eq name
        end
      end
    end

    it "sends the session cookie with a response larger than the output buffer" do
      with_web_server(Session.session) do |address|
        browser = WebSpecBrowser.new(address)
        response = browser.request("GET", "/large?name=alice")

        response.body.bytesize.should eq 200_000
        response.headers["Set-Cookie"].should contain browser.cookies[Session.config.session_key].value
        browser.get("/me").should start_with "alice|"
      end
    end

    it "saves changes made after the response started" do
      store = WebSpecSerializingStore.new
      with_web_server(store) do |address|
        browser = WebSpecBrowser.new(address)
        browser.get("/late")

        browser.get("/me").should eq "after|late flash"
      end
    end

    it "keeps the new id of a login made after the response started on the server" do
      store = WebSpecSerializingStore.new
      with_web_server(store) do |address|
        browser = WebSpecBrowser.new(address)
        old_id = browser.get("/id")
        browser.post("/late-login?name=alice")

        store[old_id]?.should be_nil
        store.find_first { |session| session.username == "alice" }.should_not be_nil
      end
    end

    it "saves the session of the request when a spawned fiber starts the response" do
      store = WebSpecSerializingStore.new
      with_web_server(store) do |address|
        browser = WebSpecBrowser.new(address)
        id = browser.get("/spawned")

        browser.cookies[Session.config.session_key].value.should eq id
        store.tracked_sessions.should eq 0
        browser.get("/me").should eq "alice|"
      end
    end
  end

  describe "context accessors" do
    it "raise a clear error when no SessionHandler served the request" do
      context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/"), HTTP::Server::Response.new(IO::Memory.new))

      expect_raises(Session::Web::MissingSession, /Session::SessionHandler/) { context.session }
      expect_raises(Session::Web::MissingSession) { context.flash }
      Session.session.current_session?.should be_nil
    end
  end

  describe "with the cookie store" do
    it "keeps a login and a flash message in the cookie" do
      with_web_server(Session::CookieStore(UserSession).new) do |address|
        browser = WebSpecBrowser.new(address)
        browser.post("/login?name=alice")

        browser.get("/me").should eq "alice|Welcome back"
        browser.get("/me").should eq "alice|"
      end
    end

    it "rejects a tampered cookie" do
      with_web_server(Session::CookieStore(UserSession).new) do |address|
        browser = WebSpecBrowser.new(address)
        browser.post("/login?name=alice")

        name = "#{Session.config.session_key}._data_"
        data = browser.cookies[name].value
        middle = data.size // 2
        flipped = data.sub(middle, data[middle] == 'A' ? 'B' : 'A')
        browser.cookies << HTTP::Cookie.new(name, flipped)

        browser.request("GET", "/me").tap do |response|
          response.status_code.should eq 200
          response.body.should eq "example|"
        end
      end
    end

    it "freezes the cookie at the first byte of the response" do
      with_web_server(Session::CookieStore(UserSession).new) do |address|
        browser = WebSpecBrowser.new(address)
        browser.get("/late")

        # Set-Cookie cannot follow the headers: what was set after the first write is not in the cookie
        browser.get("/me").should eq "before|"
      end
    end

    it "rejects a cookie signed with another secret" do
      with_web_server(Session::CookieStore(UserSession).new) do |address|
        browser = WebSpecBrowser.new(address)
        browser.post("/login?name=alice")

        Session.config.secret = "another secret, unknown to the first signer"
        browser.get("/me").should eq "example|"
      end
    end
  end

  describe "cookie attributes" do
    it "sets HttpOnly, Secure and SameSite=Strict by default" do
      with_web_server(Session.session) do |address|
        header = WebSpecBrowser.new(address).request("GET", "/id").headers["Set-Cookie"]

        header.should contain "HttpOnly"
        header.should contain "Secure"
        header.should contain "SameSite=Strict"
      end
    end

    it "follows the configuration" do
      Session.config.cookie_secure = false
      Session.config.cookie_same_site = HTTP::Cookie::SameSite::Lax

      with_web_server(Session.session) do |address|
        header = WebSpecBrowser.new(address).request("GET", "/id").headers["Set-Cookie"]

        header.should contain "HttpOnly"
        header.should_not contain "Secure"
        header.should contain "SameSite=Lax"
      end
    ensure
      Session.config.cookie_secure = true
      Session.config.cookie_same_site = HTTP::Cookie::SameSite::Strict
    end
  end

  describe "cookie option validation" do
    after_each do
      Session.config.allow_insecure_cookies = false
      Session.config.cookie_secure = true
      Session.config.cookie_same_site = HTTP::Cookie::SameSite::Strict
    end

    it "refuses SameSite=None without Secure" do
      expect_raises(Session::InvalidCookieOptions, /SameSite=None/) do
        Session.configure do |config|
          config.cookie_same_site = HTTP::Cookie::SameSite::None
          config.cookie_secure = false
        end
      end
    end

    it "refuses insecure cookies when a secure secret is required" do
      expect_raises(Session::InvalidCookieOptions, /allow_insecure_cookies/) do
        Session.configure do |config|
          config.require_secure_secret = true
          config.cookie_secure = false
        end
      end
    end

    it "accepts insecure cookies when explicitly allowed" do
      Session.configure do |config|
        config.require_secure_secret = true
        config.cookie_secure = false
        config.allow_insecure_cookies = true
      end
    end

    it "refuses to build a cookie with invalid options" do
      Session.config.cookie_same_site = HTTP::Cookie::SameSite::None
      Session.config.cookie_secure = false

      expect_raises(Session::InvalidCookieOptions) { Session.session.build_cookie("a", "b") }
    end
  end
end
