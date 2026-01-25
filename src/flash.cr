module Session
  # Flash provides temporary message storage that persists for exactly one request.
  # Messages added to `next` are available in `now` on the next request, then cleared.
  #
  # Example usage:
  #   # In controller action (e.g., after login)
  #   flash.next["notice"] = "Welcome back!"
  #
  #   # In next request (e.g., dashboard view)
  #   flash.now["notice"]  # => "Welcome back!"
  #
  #   # For same-request messages (e.g., validation errors)
  #   flash.now["error"] = "Invalid input"
  #
  class Flash
    include JSON::Serializable

    # Messages available in current request (read-only from perspective of previous request)
    getter now : Hash(String, String) = {} of String => String

    # Messages to be available in next request
    getter next : Hash(String, String) = {} of String => String

    def initialize
    end

    # Convenience method to get a flash message (checks now first)
    def [](key : String) : String?
      now[key]? || @next[key]?
    end

    # Alias for [] that explicitly returns nil when not found
    def []?(key : String) : String?
      self[key]
    end

    # Convenience method to set a flash message for next request
    def []=(key : String, value : String) : String
      @next[key] = value
    end

    # Check if a flash message exists
    def has_key?(key : String) : Bool
      now.has_key?(key) || @next.has_key?(key)
    end

    # Keep a flash message for another request
    def keep(key : String) : Nil
      if value = now[key]?
        @next[key] = value
      end
    end

    # Keep all flash messages for another request
    def keep_all : Nil
      now.each { |k, v| @next[k] = v }
    end

    # Discard a flash message (won't appear in next request)
    def discard(key : String) : Nil
      @next.delete(key)
    end

    # Discard all flash messages
    def discard_all : Nil
      @next.clear
    end

    # Clear current request messages
    def clear_now : Nil
      now.clear
    end

    # Rotate flash messages: move next -> now, clear next
    # Called automatically at start of each request
    def rotate! : Nil
      @now = @next.dup
      @next.clear
    end

    # Check if there are any flash messages
    def empty? : Bool
      now.empty? && @next.empty?
    end

    # Get all message keys
    def keys : Array(String)
      (now.keys + @next.keys).uniq
    end

    # Common flash message helpers
    def notice : String?
      self["notice"]?
    end

    def notice=(message : String) : String
      self["notice"] = message
    end

    def alert : String?
      self["alert"]?
    end

    def alert=(message : String) : String
      self["alert"] = message
    end

    def error : String?
      self["error"]?
    end

    def error=(message : String) : String
      self["error"] = message
    end

    def success : String?
      self["success"]?
    end

    def success=(message : String) : String
      self["success"] = message
    end

    def warning : String?
      self["warning"]?
    end

    def warning=(message : String) : String
      self["warning"] = message
    end

    def info : String?
      self["info"]?
    end

    def info=(message : String) : String
      self["info"] = message
    end
  end
end
