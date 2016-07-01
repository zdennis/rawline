require "spec_helper"

require_relative "../lib/rawline/keycode_parser.rb"

describe RawLine::KeycodeParser do
  subject(:keycode_parser) { described_class.new(keymap) }
  let(:keymap) { {} }

  describe "#parse_bytes_into_sequences" do
    let(:parse) do
      keycode_parser.parse_bytes_into_sequences(bytes)
    end
    let(:bytes){ fail 'Implement :bytes in context/describe for relevant example' }

    context "given a char that isn't in the keymap" do
      let(:bytes){ "a".bytes }
      it "returns the byte as a keycode" do
        expect(parse).to eq ["a"]
      end
    end

    context "given multiple characters that aren't in the keymap" do
      let(:bytes){ "abC".bytes }
      it "returns the bytes as individual keycodes" do
        expect(parse).to eq ["abC"]
      end
    end

    context "given a byte in the keymap" do
      let(:keymap) do
        { backspace: [?\C-?.ord] }
      end
      let(:bytes){ [127] }

      it "returns the bytes as a single key code" do
        expect(parse).to eq ["", [127]]
      end
    end

    context "given multiple bytes – some in the keymap, some not" do
      let(:keymap) do
        { backspace: [?\C-?.ord] }
      end
      let(:bytes) { [97, 127, 67] }

      it "returns the key codes appropriately" do
        expect(parse).to eq ["a", [127], "C"]
      end
    end

    context "given multiple bytes which make up a single keycode in the keymap" do
      let(:keymap) do
        { left_arrow: [?\e.ord, ?[.ord, ?D.ord] }
      end
      let(:bytes) { [?\e.ord, ?[.ord, ?D.ord] }

      it "returns a single key code" do
        expect(parse).to eq ["", [27, 91, 68]]
      end
    end

    context "given multiple bytes where some bytes make up a multi-byte keycode and others don't" do
      let(:keymap) do
        { left_arrow: [?\e.ord, ?[.ord, ?D.ord] }
      end
      let(:bytes) { ["a".ord, ?\e.ord, ?[.ord, ?D.ord, "C".ord] }

      it "returns a keycodes appropriately" do
        expect(parse).to eq ["a", [?\e.ord, ?[.ord, ?D.ord], "C"]
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
