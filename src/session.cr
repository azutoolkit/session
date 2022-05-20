require "uuid"
require "http"
require "json"
require "./message"
require "./provider"
require "./databag"
require "./handler"
require "./store"
require "./configuration"
require "./session_id"
require "./stores/*"

module Session
  class NotImplementedException < Exception
  end

  class InvalidSessionExeception < Exception
  end

  class InvalidSessionEventException < Exception
  end

  CONFIG = Configuration.new

  def self.configure
    with CONFIG yield CONFIG
  end

  def self.config
    CONFIG
  end

  def self.provider
    CONFIG.provider
  end
end
