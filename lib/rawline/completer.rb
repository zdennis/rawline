module RawLine

  class Completer
    def initialize(char:, line:, completion:, completion_found:, completion_not_found:, done:, keys:)
      @completion_char = char
      @line = line
      @completion_proc = completion
      @completion_found_proc = completion_found
      @completion_not_found_proc = completion_not_found
      @done_proc = done
      @keys = keys

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

      # this is to prevent a series of bytes from coming in at one time
      # E.g. holding down the tab key or arrow keys
      bytes = bytes.uniq

      if bytes.map(&:ord) == @keys[:left_arrow]
        @completion_matches.forward
        match = @completion_matches.get
        @completion_found_proc.call(completion: match, possible_completions: @completion_matches.reverse)
      elsif bytes.map(&:ord) == @keys[:right_arrow]
        @completion_matches.back
        match = @completion_matches.get
        @completion_found_proc.call(completion: match, possible_completions: @completion_matches.reverse)
      elsif bytes.map(&:ord) != @completion_char
        @done_proc.call(bytes)
      elsif @first_time
        matches = @completion_proc.call(sub_word, @line.text) unless !@completion_proc || @completion_proc == []
        matches = matches.to_a.compact.sort.reverse

        if matches.any?
          @completion_matches.resize(matches.length)
          matches.each { |w| @completion_matches << w }

          # Get first match
          @completion_matches.back
          match = @completion_matches.get

          # completion matches is a history implementation and its in reverse order from what
          # a user would expect
          @completion_found_proc.call(completion: match, possible_completions: @completion_matches.reverse)
        else
          @completion_not_found_proc.call
          @done_proc.call
        end
        @first_time = false
      else
        @completion_matches.back
        match = @completion_matches.get

        @completion_found_proc.call(completion: match, possible_completions: @completion_matches.reverse)
      end
    end

    private

    def sub_word
      @line.text[@line.word[:start]..@line.position-1] || ""
    end
  end

end
