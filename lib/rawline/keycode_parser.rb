module RawLine
  class KeycodeParser
    def initialize(keymap)
      @keymap = keymap
      @escape_code = keymap[:escape]
    end

    def parse_bytes(bytes)
      i = 0
      results = []
      loop do
        byte = bytes[i]

        keycode = find_keycode_for_multi_byte_sequence(bytes[i..-1])
        if keycode
          results << keycode
          i += keycode.length
        else
          results << byte.ord
          i += 1
        end

        break if i >= bytes.length
      end
      results
    end

    private

    # {:left_arrow=>[27, 91, 68]}
    # [27, 91, 68]
    def find_keycode_for_multi_byte_sequence(bytes)
      i = 0
      sequence = []
      loop do
        byte = bytes[i]
        if @keymap.values.any?{ |arr| arr[i] == byte }
          sequence << byte
          i += 1
        else
          break
        end
        break if i >= bytes.length
      end

      sequence.any? ? sequence : nil
    end
  end
end
