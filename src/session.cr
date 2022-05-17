require "uuid"
require "http"
require "json"
require "./provider"
require "./databag"
require "./handler"
require "./store"
require "./configuration"
require "./stores/*"
require "./session_id"
require "./manager"

module Session
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
