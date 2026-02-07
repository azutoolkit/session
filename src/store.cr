module Session
  # Abstract base class for session storage backends
  #
  # Generic Constraint:
  #   T must include the SessionData module for proper serialization and validation
  #   T must provide a parameterless constructor (T.new)
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

  # Module for stores that support querying sessions
  #
  # Generic Constraint:
  #   T must include SessionData module
  #   This module should only be included by Store(T) subclasses
  module QueryableStore(T)
    # Iterate over all sessions matching a predicate
    abstract def each_session(&block : SessionId(T) -> Nil) : Nil

    # Find sessions matching a predicate
    def find_by(&predicate : SessionId(T) -> Bool) : Array(SessionId(T))
      results = [] of SessionId(T)
      each_session do |session|
        results << session if predicate.call(session)
      end
      results
    end

    # Find first session matching a predicate
    def find_first(&predicate : SessionId(T) -> Bool) : SessionId(T)?
      result : SessionId(T)? = nil
      each_session do |session|
        if predicate.call(session)
          result = session
          break
        end
      end
      result
    end

    # Count sessions matching a predicate
    def count_by(&predicate : SessionId(T) -> Bool) : Int64
      count = 0_i64
      each_session do |session|
        count += 1 if predicate.call(session)
      end
      count
    end

    # Delete all sessions matching a predicate
    abstract def bulk_delete(&predicate : SessionId(T) -> Bool) : Int64

    # Get all session IDs
    abstract def all_session_ids : Array(String)
  end
end
