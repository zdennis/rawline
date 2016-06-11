module RawLine
  class KeycodeParser
    def initialize(keymap)
      @keymap = keymap
      @inverted_keymap = @keymap.invert
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

    def parse_bytes bytes
      if bytes.empty?
        []
      elsif bytes.any?
        results = []
        index = 0
        loop do
          sequence = byte_sequence_for(bytes[index..-1])
          results.concat sequence
          index += sequence.first.is_a?(Array) ? sequence.first.length : sequence.length
          break if index >= bytes.length
        end
        results
      end
    end

    # This returns the longer possible known byte sequence for the given
    # bytes. It returns every sequence wrapped in an array so if it knows
    # about a multi-byte sequence like :left_arrow then it will return
    # [[27,91,68]]. If it does not have a matching byte sequence it will
    # return a single element array, e.g. [12].
    def byte_sequence_for(bytes)
      if @inverted_keymap[bytes]
        [bytes]
      elsif bytes.length == 1
        bytes
      elsif bytes.length == 0
        fail "Bytes cannot be zero length"
      else
        byte_sequence_for(bytes[0..-2])
      end
    end
  end
end
