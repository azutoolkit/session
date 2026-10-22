require "./spec_helper"

describe "CookieStore request isolation" do
  it "keeps each request's cookies to the request that sent them" do
    store = Session::CookieStore(UserSession).new
    seen = Channel({String, String?}).new

    %w(alice bob).each do |name|
      spawn do
        cookies = HTTP::Cookies.new
        cookies << HTTP::Cookie.new("who", name)
        store.cookies = cookies
        Fiber.yield # the other request runs before this one reads its cookies
        seen.send({name, store.cookies["who"]?.try(&.value)})
      end
    end

    results = 2.times.map { seen.receive }.to_a.sort_by(&.first)
    results.should eq [{"alice", "alice"}, {"bob", "bob"}]
  end

  it "lets a session written in one request be read back only from that request's cookies" do
    store = Session::CookieStore(UserSession).new
    alice = UserSession.new
    alice.username = "alice"
    store[alice.session_id] = alice
    alices_cookies = store.cookies

    other = Channel(String?).new
    spawn do
      store.cookies = HTTP::Cookies.new # a visitor without a session cookie
      other.send(store[alice.session_id]?.try(&.username))
    end

    other.receive.should be_nil
    store.cookies = alices_cookies
    store[alice.session_id].username.should eq "alice"
  end

  it "does not keep the cookies of requests that are over" do
    store = Session::CookieStore(UserSession).new
    done = Channel(Nil).new
    50.times { spawn { store.cookies = HTTP::Cookies.new; done.send(nil) } }
    50.times { done.receive }
    Fiber.yield

    store.cookies = HTTP::Cookies.new
    store.@request_cookies.size.should be < 5
  end
end
