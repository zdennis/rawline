module RawLine
  class Editor
    class Environment
      attr_accessor :completion_class

      attr_accessor :history
      attr_accessor :history_size
      attr_accessor :line_history_size

      attr_accessor :word_break_characters
      attr_accessor :word_separator

      def initialize(env: nil)
        @env = env
        @completion_class = Completer
        @word_break_characters = " \t\n\"'@><=;|&{()}"

        @line_history_size = 50
        @history_size = 30
        @history = HistoryBuffer.new(@history_size) do |h|
          h.duplicates = false;
          h.exclude = lambda { |item| item.strip == "" }
        end
      end

      def word_break_characters=(str)
        @word_break_characters = str
        update_word_separator
      end

      protected

      def update_word_separator
        return @word_separator = "" if @word_break_characters.to_s == ""
        chars = []
        @word_break_characters.each_byte do |c|
          ch = (c.is_a? Fixnum) ? c : c.ord
          value = (ch == ?\s.ord) ? ' ' : Regexp.escape(ch.chr).to_s
          chars << value
        end
        @word_separator = /(?<!\\)[#{chars.join}]/
      end

    end
  end
end
