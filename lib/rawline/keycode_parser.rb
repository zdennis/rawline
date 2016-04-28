module RawLine
  class KeycodeParser
    def initialize(keymap)
      @keymap = keymap
      @escape_code = keymap[:escape]
    end

    # Parses a collection of bytes into key code sequences. All
    # multi-byte sequences (e.g. [27, 91, 67]) will be left alone where-as
    # all other byte sequences will be converted to UTF-8.
    #
    # E.g.
    #    parse_bytes_into_sequences [97, 98, [27, 91, 67], 99, 198, 146]
    #    # => ["a", "b", [27, 91, 67], "c", "ƒ"]
    #
    def parse_bytes_into_sequences(bytes)
      key_codes = parse_bytes(bytes)

      byte_buffer = []
      sequences = key_codes.each_with_object([]) do |val, arr|
        if val.is_a?(Array)
          arr.push *convert_bytes_to_utf8(byte_buffer)
          arr << val
          byte_buffer = []
        else
          byte_buffer << val
        end
      end

      # don't forget about remaining bytes in the buffer
      if byte_buffer.any?
        sequences.push *convert_bytes_to_utf8(byte_buffer)
      end

      sequences
    end

    private

    def convert_bytes_to_utf8(bytes)
      bytes.pack('C*').force_encoding('UTF-8')
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
