module RawLine
  module Modes
    class TabCompletionMode
      include Editor::MajorMode

      def self.name
        :'tab-completion'
      end

      attr_reader :env, :previous_mode
      attr_accessor :bubble_input
      attr_accessor :match_hidden_files

      def initialize(previous: nil, bubble_input: true)
        @previous_mode = previous
        @bubble_input = bubble_input
        @match_hidden_files = false
      end

      def bubble_input?
        !!@bubble_input
      end

      def completion_class
        Completer
      end

      def completion_char
        @completion_char || ["\t"].map(&:ord)
      end

      def activate(editor)
        @editor = editor

        @completion_proc = editor.completion_proc || filename_completion_proc
        @on_word_complete = editor.on_word_complete
        @on_word_complete_no_match = editor.on_word_complete_no_match
        @on_word_complete_done = editor.on_word_complete_done
        @on_word_completion_selected = editor.on_word_completion_selected

        @completer = initialize_completer
        @completer.read_bytes [completion_char]
      end

      def deactivate(editor)
      end

      def read_bytes(bytes)
        @completer.read_bytes(bytes)
      end

      private

      def completion_found(completion:, possible_completions:)
        Treefell['editor'].puts "word-completion-found: #{completion.inspect} possible_completions: #{possible_completions.inspect}"
        if @on_word_complete
          word = @editor.line.word[:text]
          sub_word = @editor.line.text[@editor.line.word[:start]..@editor.line.position-1] || ""
          @on_word_complete.call(name: "word-completion", payload: { sub_word: sub_word, word: word, completion: completion, possible_completions: possible_completions })
        end

        completion_selected(completion)
      end

      def completion_selected(completion)
        Treefell['editor'].puts "word-completion-selected #{completion.inspect}"
        @editor.move_to_position @editor.line.word[:end]
        @editor.delete_n_characters(@editor.line.word[:end] - @editor.line.word[:start], true)
        @editor.write completion.to_s

        if @on_word_completion_selected
          Treefell['editor'].puts "word-completion-selected callback called with #{completioni}"
          @on_word_completion_selected.call(name: "word-completion-selected", payload: { completion: completion })
        end
      end

      def completion_not_found
        Treefell['editor'].puts 'word-completion-not-found'
        if @on_word_complete_no_match
          word = @editor.line.word[:text]
          sub_word = @editor.line.text[@editor.line.word[:start]..@editor.line.position-1] || ""
          payload = { sub_word: sub_word, word: word }
          Treefell['editor'].puts "word-completion-not-found calling callback with payload: #{payload.inspect}"
          @on_word_complete_no_match.call(name: "word-completion-no-match", payload: payload)
        else
          Treefell['editor'].puts 'word-completion-not-found no on_word_complete_no_match callback to call'
        end
      end

      def completion_done
        if @on_word_complete_done
          Treefell['editor'].puts "word-completion-done calling on_word_complete_done callback"
          @on_word_complete_done.call
        else
          Treefell['editor'].puts 'word-completion-done no on_word_complete_done callback to call'
        end
      end

      #
      # Complete file and directory names.
      # Hidden files and directories are matched only if <tt>@match_hidden_files</tt> is true.
      #
      def filename_completion_proc
        lambda do |word, _|
          dirs = @editor.line.text.split('/')
            path = @editor.line.text.match(/^\/|[a-zA-Z]:\//) ? "/" : Dir.pwd+"/"
          if dirs.length == 0 then # starting directory
            dir = path
          else
            dirs.delete(dirs.last) unless File.directory?(path+dirs.join('/'))
            dir = path+dirs.join('/')
          end
          Dir.entries(dir).select { |e| (e =~ /^\./ && @match_hidden_files && word == '') || (e =~ /^#{word}/ && e !~ /^\./) }
        end
      end

      def initialize_completer
        completion_class.new(
          char: completion_char,
          line: @editor.line,
          completion: @completion_proc,
          completion_found: -> (completion:, possible_completions:) {
            completion_found(completion: completion, possible_completions: possible_completions)
          },
          completion_not_found: -> {
            completion_not_found
          },
          completion_selected: -> (completion) {
            completion_selected(completion)
          },
          done: -> {
            completion_done
            @editor.deactivate_mode(self.class.name)
          },
          keys: @editor.terminal.keys
        )
      end
    end
  end
end
