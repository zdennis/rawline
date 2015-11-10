require "spec_helper"

require_relative "../lib/rawline/keycode_parser.rb"

describe RawLine::KeycodeParser do
  subject(:keycode_parser) { described_class.new(keymap) }
  let(:keymap) { {} }

  describe "#parse_bytes" do
    def parse_bytes(bytes)
      keycode_parser.parse_bytes(bytes)
    end

    context "given a char that isn't in the keymap" do
      it "returns the byte as a keycode" do
        expect(parse_bytes(["a"])).to eq ["a".ord]
      end
    end

    context "given a char that isn't in the keymap" do
      it "returns the byte as a keycode" do
        expect(parse_bytes([97])).to eq ["a".ord]
      end
    end

    context "given multiple characters that aren't in the keymap" do
      it "returns the bytes as individual keycodes" do
        expect(parse_bytes(["a", "b", "C"])).to eq ["a", "b", "C"].map(&:ord)
      end
    end

    context "given multiple characters that aren't in the keymap" do
      it "returns the bytes as individual keycodes" do
        expect(parse_bytes([97, 98, 67])).to eq ["a", "b", "C"].map(&:ord)
      end
    end

    context "given a byte in the keymap" do
      let(:keymap) do
        { backspace: [?\C-?.ord] }
      end

      it "returns the bytes as a single key code" do
        expect(parse_bytes([127])).to eq [[127]]
      end
    end

    context "given multiple bytes – some in the keymap, some not" do
      let(:keymap) do
        { backspace: [?\C-?.ord] }
      end

      it "returns the key codes appropriately" do
        expect(parse_bytes([97, 127, 67])).to eq [97, [127], 67]
      end
    end

    context "given multiple bytes which make up a single keycode in the keymap" do
      let(:keymap) do
        { left_arrow: [?\e.ord, ?[.ord, ?D.ord] }
      end

      it "returns a single key code" do
        expect(parse_bytes([?\e.ord, ?[.ord, ?D.ord])).to eq [[?\e.ord, ?[.ord, ?D.ord]]
      end
    end

    context "given multiple bytes where some bytes make up a multi-byte keycode and others don't" do
      let(:keymap) do
        { left_arrow: [?\e.ord, ?[.ord, ?D.ord] }
      end

      it "returns a keycodes appropriately" do
        expect(parse_bytes([97, ?\e.ord, ?[.ord, ?D.ord, 67])).to eq [97, [?\e.ord, ?[.ord, ?D.ord], 67]
      end
    end

  end

end


__END__
      @escape_codes = [?\e.ord]
      @keys.merge!(
        {
          :up_arrow => [?\e.ord, ?[.ord, ?A.ord],
          :down_arrow => [?\e.ord, ?[.ord, ?B.ord],
          :right_arrow => [?\e.ord, ?[.ord, ?C.ord],
          :left_arrow => [?\e.ord, ?[.ord, ?D.ord],
          :insert => [?\e.ord, ?[, ?2.ord, ?~.ord],
          :delete => [?\e.ord, ?[, ?3.ord, ?~.ord],
          :backspace => [?\C-?.ord],
          :enter => (HighLine::SystemExtensions::CHARACTER_MODE == 'termios' ? [?\n.ord] : [?\r.ord]),

          :ctrl_alt_a => [?\e.ord, ?\C-a.ord],
