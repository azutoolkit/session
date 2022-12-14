module Session
  abstract class Store(T)
    include Provider

    abstract def [](key : String) : SessionId(T)
    abstract def []?(key : String) : SessionId(T)?
    abstract def []=(key : String, session : SessionId(T)) : SessionId(T)
    abstract def delete(key : String)
    abstract def size : Int64
    abstract def clear

    def self.provider(**args) : Store(T)
      new(**args)
    end
  end
end
