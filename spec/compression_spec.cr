require "./spec_helper"

describe Session::Compression do
  # Save and restore config around tests that modify it
  original_compress_data = Session.config.compress_data
  original_threshold = Session.config.compression_threshold

  after_each do
    Session.config.compress_data = original_compress_data
    Session.config.compression_threshold = original_threshold
  end

  describe ".compress" do
    it "compresses data" do
      original = "Hello, World! " * 100 # Repetitive data compresses well
      compressed = Session::Compression.compress(original)

      compressed.bytesize.should be < original.bytesize
    end

    it "produces gzip magic bytes" do
      compressed = Session::Compression.compress("test data")
      compressed[0, 2].should eq "\x1F\x8B"
    end
  end

  describe ".decompress" do
    it "decompresses data" do
      original = "Hello, World! " * 100
      compressed = Session::Compression.compress(original)
      decompressed = Session::Compression.decompress(compressed)

      decompressed.should eq original
    end

    it "handles short data" do
      original = "short"
      compressed = Session::Compression.compress(original)
      decompressed = Session::Compression.decompress(compressed)

      decompressed.should eq original
    end
  end

  describe ".compressed?" do
    it "returns true for compressed data" do
      compressed = Session::Compression.compress("test")
      Session::Compression.compressed?(compressed).should be_true
    end

    it "returns false for uncompressed data" do
      Session::Compression.compressed?("plain text").should be_false
    end

    it "returns false for empty string" do
      Session::Compression.compressed?("").should be_false
    end

    it "returns false for single byte" do
      Session::Compression.compressed?("a").should be_false
    end
  end

  describe ".compress_if_enabled" do
    it "returns original when compression disabled" do
      Session.config.compress_data = false
      original = "test data " * 100

      result = Session::Compression.compress_if_enabled(original)
      result.should eq original
    end

    it "compresses when enabled and above threshold" do
      Session.config.compress_data = true
      Session.config.compression_threshold = 50
      original = "test data " * 100 # Well above threshold

      result = Session::Compression.compress_if_enabled(original)
      result.should_not eq original
      Session::Compression.compressed?(result).should be_true
    end

    it "returns original when below threshold" do
      Session.config.compress_data = true
      Session.config.compression_threshold = 1000
      original = "short" # Below threshold

      result = Session::Compression.compress_if_enabled(original)
      result.should eq original
    end
  end

  describe ".decompress_if_needed" do
    it "decompresses compressed data" do
      original = "test data"
      compressed = Session::Compression.compress(original)

      result = Session::Compression.decompress_if_needed(compressed)
      result.should eq original
    end

    it "returns uncompressed data as-is" do
      original = "plain text"

      result = Session::Compression.decompress_if_needed(original)
      result.should eq original
    end
  end

  describe ".compression_ratio" do
    it "calculates ratio correctly" do
      original = "test " * 100
      compressed = Session::Compression.compress(original)

      ratio = Session::Compression.compression_ratio(original, compressed)
      ratio.should be < 1.0 # Compressed should be smaller
    end

    it "handles empty string" do
      ratio = Session::Compression.compression_ratio("", "")
      ratio.should eq 1.0
    end
  end
end
