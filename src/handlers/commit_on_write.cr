module Session
  # Wraps a response's output and runs a block once, just before the first byte is written.
  #
  # Response headers, `Set-Cookie` among them, are sent with the first write. A session saved
  # after the endpoint returns is too late for a response that was flushed, streamed, or larger
  # than the output buffer, and its cookie would be lost.
  class CommitOnWrite < IO
    def initialize(@io : IO, &@commit : ->)
      @committed = false
    end

    def commit : Nil
      return if @committed
      @committed = true
      @commit.call
    end

    def read(slice : Bytes) : NoReturn
      raise IO::Error.new("A response output cannot be read")
    end

    def write(slice : Bytes) : Nil
      commit
      @io.write(slice)
    end

    def flush : self
      commit
      @io.flush
      self
    end

    def close : Nil
      commit
      @io.close
    end

    def closed? : Bool
      @io.closed?
    end
  end
end
