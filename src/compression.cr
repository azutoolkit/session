require "compress/gzip"

module Session
  module Compression
    extend self

    # Magic bytes to identify compressed data
    COMPRESSION_MARKER = "\x1F\x8B" # Gzip magic number

    # Compress data if compression is enabled and data exceeds threshold
    def compress_if_enabled(data : String) : String
      return data unless Session.config.compress_data
      return data if data.bytesize < Session.config.compression_threshold

      compress(data)
    end

    # Decompress data if it appears to be compressed
    def decompress_if_needed(data : String) : String
      return data unless compressed?(data)

      decompress(data)
    end

    # Check if data appears to be gzip compressed
    def compressed?(data : String) : Bool
      data.bytesize >= 2 && data[0, 2] == COMPRESSION_MARKER
    end

    # Compress data using gzip
    def compress(data : String) : String
      io = IO::Memory.new
      Compress::Gzip::Writer.open(io) do |gzip|
        gzip.print(data)
      end
      io.to_s
    rescue ex : Exception
      Log.warn { "Compression failed, using uncompressed data: #{ex.message}" }
      data
    end

    # Decompress gzip data
    def decompress(data : String) : String
      io = IO::Memory.new(data)
      result = Compress::Gzip::Reader.open(io) do |gzip|
        gzip.gets_to_end
      end
      result
    rescue ex : Exception
      Log.warn { "Decompression failed: #{ex.message}" }
      raise SessionCorruptionException.new("Failed to decompress session data", ex)
    end

    # Get compression ratio for debugging/metrics
    def compression_ratio(original : String, compressed : String) : Float64
      return 1.0 if original.bytesize == 0
      compressed.bytesize.to_f64 / original.bytesize.to_f64
    end
  end
end
