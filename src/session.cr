require "uuid"
require "http"
require "json"
require "./message"
require "./provider"
require "./session_data"
require "./handlers/*"
require "./store"
require "./metrics"
require "./compression"
require "./flash"
require "./binding"
require "./configuration"
require "./session_id"
require "./stores/*"
require "./retry"
require "./connection_pool"

module Session
  Log = ::Log.for("session")

  # Specific exception types for better error handling
  class SessionExpiredException < Exception
    def initialize(message : String = "Session has expired", cause : Exception? = nil)
      super(message, cause)
    end
  end

  class SessionCorruptionException < Exception
    def initialize(message : String = "Session data is corrupted", cause : Exception? = nil)
      super(message, cause)
    end
  end

  class StorageConnectionException < Exception
    def initialize(message : String = "Storage connection failed", cause : Exception? = nil)
      super(message, cause)
    end
  end

  class SessionNotFoundException < Exception
    def initialize(message : String = "Session not found", cause : Exception? = nil)
      super(message, cause)
    end
  end

  class SessionValidationException < Exception
    def initialize(message : String = "Session validation failed", cause : Exception? = nil)
      super(message, cause)
    end
  end

  class SessionSerializationException < Exception
    def initialize(message : String = "Session serialization failed", cause : Exception? = nil)
      super(message, cause)
    end
  end

  class SessionEncryptionException < Exception
    def initialize(message : String = "Session encryption/decryption failed", cause : Exception? = nil)
      super(message, cause)
    end
  end

  class CookieSizeExceededException < Exception
    MAX_COOKIE_SIZE = 4096

    getter actual_size : Int32
    getter max_size : Int32

    def initialize(actual_size : Int32, max_size : Int32 = MAX_COOKIE_SIZE, cause : Exception? = nil)
      @actual_size = actual_size
      @max_size = max_size
      super("Cookie size #{actual_size} bytes exceeds maximum allowed size of #{max_size} bytes", cause)
    end
  end

  class SessionBindingException < Exception
    getter binding_type : String

    def initialize(@binding_type : String, message : String? = nil, cause : Exception? = nil)
      super(message || "Session binding validation failed for #{binding_type}", cause)
    end
  end

  # Legacy exceptions for backward compatibility
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
