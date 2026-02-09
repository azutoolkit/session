require "./spec_helper"

describe Session::Flash do
  describe "#initialize" do
    it "creates empty flash" do
      flash = Session::Flash.new
      flash.empty?.should be_true
      flash.now.empty?.should be_true
      flash.next.empty?.should be_true
    end
  end

  describe "#[]=" do
    it "sets message for next request" do
      flash = Session::Flash.new
      flash["notice"] = "Hello"

      flash.next["notice"].should eq "Hello"
      flash.now["notice"]?.should be_nil
    end
  end

  describe "#[]" do
    it "gets from now first" do
      flash = Session::Flash.new
      flash.now["notice"] = "from now"
      flash.next["notice"] = "from next"

      flash["notice"].should eq "from now"
    end

    it "falls back to next" do
      flash = Session::Flash.new
      flash.next["notice"] = "from next"

      flash["notice"].should eq "from next"
    end

    it "returns nil when not found" do
      flash = Session::Flash.new
      flash["missing"]?.should be_nil
    end
  end

  describe "#rotate!" do
    it "moves next to now" do
      flash = Session::Flash.new
      flash["notice"] = "Hello"
      flash["alert"] = "Warning"

      flash.rotate!

      flash.now["notice"].should eq "Hello"
      flash.now["alert"].should eq "Warning"
      flash.next.empty?.should be_true
    end

    it "clears previous now" do
      flash = Session::Flash.new
      flash.now["old"] = "value"
      flash["new"] = "value"

      flash.rotate!

      flash.now["old"]?.should be_nil
      flash.now["new"].should eq "value"
    end
  end

  describe "#keep" do
    it "keeps a message for another request" do
      flash = Session::Flash.new
      flash.now["notice"] = "Keep me"

      flash.keep("notice")

      flash.next["notice"].should eq "Keep me"
    end

    it "does nothing for non-existent key" do
      flash = Session::Flash.new
      flash.keep("missing")
      flash.next["missing"]?.should be_nil
    end
  end

  describe "#keep_all" do
    it "keeps all messages" do
      flash = Session::Flash.new
      flash.now["notice"] = "Notice"
      flash.now["alert"] = "Alert"

      flash.keep_all

      flash.next["notice"].should eq "Notice"
      flash.next["alert"].should eq "Alert"
    end
  end

  describe "#discard" do
    it "removes message from next" do
      flash = Session::Flash.new
      flash["notice"] = "Discard me"

      flash.discard("notice")

      flash.next["notice"]?.should be_nil
    end
  end

  describe "#discard_all" do
    it "clears all next messages" do
      flash = Session::Flash.new
      flash["notice"] = "One"
      flash["alert"] = "Two"

      flash.discard_all

      flash.next.empty?.should be_true
    end
  end

  describe "#empty?" do
    it "returns true when both empty" do
      flash = Session::Flash.new
      flash.empty?.should be_true
    end

    it "returns false when now has messages" do
      flash = Session::Flash.new
      flash.now["notice"] = "Hello"
      flash.empty?.should be_false
    end

    it "returns false when next has messages" do
      flash = Session::Flash.new
      flash["notice"] = "Hello"
      flash.empty?.should be_false
    end
  end

  describe "#keys" do
    it "returns all unique keys" do
      flash = Session::Flash.new
      flash.now["notice"] = "Now"
      flash["alert"] = "Next"
      flash["notice"] = "Also next" # Duplicate key

      keys = flash.keys
      keys.should contain("notice")
      keys.should contain("alert")
      keys.size.should eq 2
    end
  end

  describe "convenience methods" do
    it "provides notice accessor" do
      flash = Session::Flash.new
      flash.notice = "Test notice"
      flash.notice.should eq "Test notice"
    end

    it "provides alert accessor" do
      flash = Session::Flash.new
      flash.alert = "Test alert"
      flash.alert.should eq "Test alert"
    end

    it "provides error accessor" do
      flash = Session::Flash.new
      flash.error = "Test error"
      flash.error.should eq "Test error"
    end

    it "provides success accessor" do
      flash = Session::Flash.new
      flash.success = "Test success"
      flash.success.should eq "Test success"
    end

    it "provides warning accessor" do
      flash = Session::Flash.new
      flash.warning = "Test warning"
      flash.warning.should eq "Test warning"
    end

    it "provides info accessor" do
      flash = Session::Flash.new
      flash.info = "Test info"
      flash.info.should eq "Test info"
    end
  end

  describe "#has_key?" do
    it "returns true when key exists in now" do
      flash = Session::Flash.new
      flash.now["notice"] = "Hello"

      flash.has_key?("notice").should be_true
    end

    it "returns true when key exists in next" do
      flash = Session::Flash.new
      flash["alert"] = "Warning"

      flash.has_key?("alert").should be_true
    end

    it "returns false when key does not exist" do
      flash = Session::Flash.new

      flash.has_key?("missing").should be_false
    end
  end

  describe "#clear_now" do
    it "clears current request messages" do
      flash = Session::Flash.new
      flash.now["notice"] = "Current"
      flash.now["alert"] = "Also current"

      flash.clear_now

      flash.now.empty?.should be_true
    end

    it "does not affect next messages" do
      flash = Session::Flash.new
      flash.now["notice"] = "Current"
      flash["alert"] = "Next"

      flash.clear_now

      flash.now.empty?.should be_true
      flash.next["alert"].should eq "Next"
    end
  end

  describe "keep across rotations" do
    it "survives two rotations with keep" do
      flash = Session::Flash.new
      flash["notice"] = "Persistent"

      # First rotation: next -> now
      flash.rotate!
      flash.now["notice"].should eq "Persistent"

      # Keep it for another request
      flash.keep("notice")

      # Second rotation: next -> now again
      flash.rotate!
      flash.now["notice"].should eq "Persistent"
    end

    it "disappears after rotation without keep" do
      flash = Session::Flash.new
      flash["notice"] = "Ephemeral"

      flash.rotate!
      flash.now["notice"].should eq "Ephemeral"

      # Don't keep, rotate again
      flash.rotate!
      flash.now["notice"]?.should be_nil
    end
  end

  describe "JSON serialization" do
    it "serializes and deserializes" do
      flash = Session::Flash.new
      flash.now["notice"] = "Now message"
      flash["alert"] = "Next message"

      json = flash.to_json
      restored = Session::Flash.from_json(json)

      restored.now["notice"].should eq "Now message"
      restored.next["alert"].should eq "Next message"
    end
  end
end
