require "spec"
require "../src/session"

REDIS_HOST = ENV["REDIS_HOST"]? || "localhost"

REDIS_CLIENT = Redis.new(host: REDIS_HOST)

class UserSession
  include Session::SessionData
  property? authenticated : Bool = true
  property username : String? = "example"
end

Session.configure do
  on_started = ->(sid : String, data : Session::SessionData) { puts "Session started - Id: #{sid} Username: #{data.username}" }
  on_deleted = ->(sid : String, data : Session::SessionData) { puts "Session Revoke - Id: #{sid} Username: #{data.username}" }
end
