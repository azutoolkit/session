require "spec"
require "../src/session"

record UserSession, username : String? = "example" do
  include JSON::Serializable
end
