module RawLine

  class Completer
    def initialize(char:, line:, completion:, completion_updated:, done:)
      @completion_char = char
      @line = line
      @completion_proc = completion
      @completion_updated_proc = completion_updated
      @done_proc = done

      @completion_matches = HistoryBuffer.new(0) do |h|
        h.duplicates = false
        h.cycle = true
      end
      @completion_matches.empty

      @first_time = true
      @word_start = @line.word[:start]
    end

    def read_bytes(bytes)
      return unless bytes.any?

      if bytes.map(&:ord) != @completion_char
        @done_proc.call(bytes)
      elsif @first_time
        matches = @completion_proc.call(sub_word) unless !@completion_proc || @completion_proc == []
        matches = matches.to_a.compact.sort.reverse

        if matches.any?
          @completion_matches.resize(matches.length)
          matches.each { |w| @completion_matches << w }

          # Get first match
          @completion_matches.back
          match = @completion_matches.get

          @completion_updated_proc.call(match)
        else
          @done_proc.call
        end
        @first_time = false
      else
        @completion_matches.back
        match = @completion_matches.get
        @completion_updated_proc.call(match)
      end
    end

    private

    def sub_word
      @line.text[@line.word[:start]..@line.position-1] || ""
    end
  end

end
