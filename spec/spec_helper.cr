require "spec"
require "../src/session"

REDIS_HOST = ENV["REDIS_HOST"]? || "localhost"

REDIS_CLIENT = Redis.new host: REDIS_HOST

class UserSession
  include Session::Databag
  property username : String? = "example"
end

Session.configure do |c|
  c.on_started = ->(sid : String) { puts "Session started - #{sid}" }
  c.on_deleted = ->(sid : String) { puts "Session Revoke - #{sid}" }
end
