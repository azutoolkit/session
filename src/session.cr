require "uuid"
require "http"
require "json"
require "./message"
require "./provider"
require "./databag"
require "./handlers/*"
require "./store"
require "./configuration"
require "./session_id"
require "./stores/*"

module Session
  Log = ::Log.for("session")

  class NotImplementedException < Exception
  end

  class InvalidSessionExeception < Exception
  end

  class InvalidSessionEventException < Exception
  end

  CONFIG = Configuration.new

  def self.configure(&)
    with CONFIG yield CONFIG
  end

  def self.config
    CONFIG
  end

  def self.session
    CONFIG.session
  end
end
