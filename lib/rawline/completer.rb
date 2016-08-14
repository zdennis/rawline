module RawLine

  class Completer
    def initialize(char:, line:, completion:, completion_found:, completion_not_found:, completion_selected:, done:, keys:)
      @completion_char = char
      @line = line
      @completion_proc = completion
      @completion_found_proc = completion_found
      @completion_not_found_proc = completion_not_found
      @completion_selected_proc = completion_selected
      @done_proc = done
      @keys = keys

      @completion_matches = HistoryBuffer.new_with_infinite_size(
        cycle: true,
        duplicates: false
      )

      @first_time = true
      @word_start = @line.word[:start]
    end

    def read_bytes(bytes)
      return [] unless bytes.any?

      # this is to prevent a series of bytes from coming in at one time
      # E.g. holding down the tab key or arrow keys
      bytes = bytes.uniq

      if @first_time
        matches = fetch_completions
        @completion_matches.replace(matches)
        @completion_matches.first!

        if matches.length == 1
          handle_one_match
        elsif matches.length > 1
          handle_more_than_one_match
        else
          handle_no_completions
        end

        @first_time = false
      elsif bytes == @keys[:left_arrow]
        select_previous
      elsif bytes == @keys[:right_arrow]
        select_next
      elsif bytes == @completion_char
        select_next
      else
        Treefell['editor'].puts "completer, done with leftover bytes: #{bytes.inspect}"
        @done_proc.call
        return bytes
      end
      []
    end

    private

    def fetch_completions
      if @completion_proc && @completion_proc.respond_to?(:call)
        word = @line.text[@line.word[:start]..@line.position-1] || ""
        words = @line.text
          .split(/\s+/)
          .delete_if(&:empty?)
        word_index = words.index(word)
        Treefell['editor'].puts "completer, looking for completions word=#{word.inspect} words=#{words.inspect} word_index=#{word_index}"
        matches = @completion_proc.call(
          word,
          words,
          word_index
        )
      end

      # Always return an array so the caller doesn't have
      # to worry about nil
      matches.to_a.compact
    end

    def handle_one_match
      Treefell['editor'].puts "completer, exactly one possible completion found: #{@completion_matches.inspect}"
      @completion_selected_proc.call(@completion_matches.get)

      Treefell['editor'].puts "completer, done"
      @done_proc.call
    end

    def handle_more_than_one_match
      Treefell['editor'].puts "completer, more than one possible completion"
      match = @completion_matches.get

      Treefell['editor'].puts "completer: first completion: #{match} possible: #{@completion_matches.inspect}"
      @completion_found_proc.call(completion: match, possible_completions: @completion_matches)
    end

    def handle_no_completions
      Treefell['editor'].puts "completer, no possible completions found"
      @completion_not_found_proc.call

      Treefell['editor'].puts "completer, done"
      @done_proc.call
    end

    def select_next
      @completion_matches.forward
      match = @completion_matches.get

      Treefell['editor'].puts "completer, selecting next match=#{match.inspect} possible_completions=#{@completion_matches.inspect}"
      @completion_found_proc.call(completion: match, possible_completions: @completion_matches)
    end

    def select_previous
      @completion_matches.back
      match = @completion_matches.get

      Treefell['editor'].puts "completer, selecting previous match=#{match.inspect} possible_completions=#{@completion_matches.inspect}"
      @completion_found_proc.call(completion: match, possible_completions: @completion_matches)
    end
  end
end
