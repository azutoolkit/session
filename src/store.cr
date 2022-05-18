module Session
  module Store(T)
    macro included
      def self.provider(**args) : Manager(T)
        store = new(**args)
        Manager(T).new(store)
      end
    end

    abstract def [](key : String) : SessionId(T)
    abstract def []?(key : String) : SessionId(T)?
    abstract def []=(key : String, session_id : SessionId(T)) : SessionId(T)
    abstract def delete(key : String)
    abstract def size : Int64
    abstract def clear
  end
end
