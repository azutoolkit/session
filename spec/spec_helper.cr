require "spec"
require "../src/session"

REDIS_HOST = ENV["REDIS_HOST"]? || "localhost"

REDIS_CLIENT = Redis.new host: REDIS_HOST

class UserSession
  include Session::Databag
  property? authenticated : Bool = true
  property username : String? = "example"
end

Session.configure do
  c.on_started = ->(sid : String, data : Session::Databag) { puts "Session started - Id: #{sid} Username: #{data.username}" }
  c.on_deleted = ->(sid : String, data : Session::Databag) { puts "Session Revoke - Id: #{sid} Username: #{data.username}" }
end
