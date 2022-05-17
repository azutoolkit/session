module Session
  module Databag
    macro included
      include JSON::Serializable

      def initialize
      end
    end
  end

  
end
