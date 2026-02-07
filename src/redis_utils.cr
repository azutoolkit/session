require "redis"

module Session
  # Utility methods for Redis operations to reduce code duplication
  module RedisUtils
    # Scan all keys matching a pattern and yield each key
    def self.scan_keys(client : Redis, pattern : String, batch_size : Int32 = 100, &block : String -> Nil)
      cursor = "0"

      loop do
        result = client.scan(cursor, match: pattern, count: batch_size)
        cursor = result[0].as(String)
        keys = result[1].as(Array(Redis::RedisValue))

        keys.each do |key|
          yield key.as(String)
        end

        break if cursor == "0"
      end
    end

    # Count all keys matching a pattern
    def self.count_keys(client : Redis, pattern : String, batch_size : Int32 = 100) : Int64
      count = 0_i64
      scan_keys(client, pattern, batch_size) { count += 1 }
      count
    end

    # Delete all keys matching a pattern
    def self.delete_keys(client : Redis, pattern : String, batch_size : Int32 = 100) : Int64
      deleted = 0_i64
      keys_to_delete = [] of String

      scan_keys(client, pattern, batch_size) do |key|
        keys_to_delete << key

        # Delete in batches to avoid memory issues
        if keys_to_delete.size >= batch_size
          client.del(keys_to_delete)
          deleted += keys_to_delete.size.to_i64
          keys_to_delete.clear
        end
      end

      # Delete remaining keys
      unless keys_to_delete.empty?
        client.del(keys_to_delete)
        deleted += keys_to_delete.size.to_i64
      end

      deleted
    end

    # Collect all keys matching a pattern
    def self.collect_keys(client : Redis, pattern : String, batch_size : Int32 = 100) : Array(String)
      keys = [] of String
      scan_keys(client, pattern, batch_size) { |key| keys << key }
      keys
    end
  end
end
