module Session
  module Databag
    abstract def authenticated? : Bool

    macro included
      include JSON::Serializable

      def initialize
      end
    end
  end
end
