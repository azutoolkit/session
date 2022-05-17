require "spec"
require "../src/session"

class UserSession
  include Session::Databag
  property username : String? = "example"
end
