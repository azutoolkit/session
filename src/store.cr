module Session
  module Store(T)
    abstract def [](key : String) : SessionId(T)
    abstract def []?(key : String) : SessionId(T)?
    abstract def set(key : String, session_id : SessionId(T), expires : Time::Span) : SessionId(T)
    abstract def delete(key : String)
    abstract def size : Int64
  end
end
