require 'rawline/editor/major_mode'

module RawLine
  module Modes
    class NormalMode
      include Editor::MajorMode

      def self.name
        :normal
      end

      attr_reader :env
      attr_accessor :bubble_input

      def initialize(previous: nil, bubble_input: false)
        @previous_mode = previous
        @bubble_input = bubble_input
      end

      def initialize_line(&blk)
        Line.new(env.line_history_size) do |line|
          line.word_separator = env.word_separator
          blk.call(line) if blk
        end
      end

      def activate(editor)
        @editor = editor
        @keys = KeyBindings.new(terminal: @editor.terminal)
        @env = Editor::Environment.new
        install_key_bindings
      end

      def bubble_input?
        !!@bubble_input
      end

      def deactivate(editor)
        # no-op
      end

      def read_bytes(bytes)
        return unless bytes.any?

        Treefell['editor'].puts "read_bytes #{bytes.inspect}"
        old_position = @editor.line.position

        key_code_sequences = parse_key_code_sequences(bytes)

        Treefell['editor'].puts "key code sequences: #{key_code_sequences.inspect}"
        begin
          key_code_sequences.each do |sequence|
            if sequence == @editor.terminal.keys[:enter] || !sequence
              Treefell['editor'].puts "processing line: #{@editor.line.text.inspect}"
              @editor.process_line
            else
              process_character(sequence)
              new_position = @editor.line.position
            end
          end
        end
        []
      end

      def bind(key, &blk)
        @keys.bind(key, &blk)
      end

      def unbind(key)
        @keys.unbind(key)
      end

      def key_bound?(bytes)
        key_binding_for_bytes[bytes] ? true : false
      end

      protected

      #
      # Execute the default action for the last character read via <tt>read</tt>.
      # By default it prints the character to the screen via <tt>write</tt>.
      # This method is called automatically by <tt>process_character</tt>.
      #
      def default_action(byte_sequence)
        @editor.insert(byte_sequence)
      end

      def install_key_bindings
        bind(:space) { @editor.insert(' ') }
        bind(:enter) { @editor.newline }
        bind(:tab) { @editor.complete }
        bind(:backspace) { @editor.delete_left_character }
        bind(:ctrl_c) { raise Interrupt }
        bind(:ctrl_k) { @editor.clear_line }
        bind(:ctrl_u) { @editor.undo }
        bind(:ctrl_r) { @editor.redo }
        bind(:left_arrow) { @editor.move_left }
        bind(:right_arrow) { @editor.move_right }
        bind(:up_arrow) { @editor.history_back }
        bind(:down_arrow) { @editor.history_forward }
        bind(:delete) { @editor.delete_character }
        bind(:insert) { @editor.toggle_mode }
      end

      def key_binding_for_bytes(bytes)
        @keys[bytes]
      end

      #
      # Parse a key or key sequence into the corresponding codes.
      #
      def parse_key_code_sequences(bytes)
        KeycodeParser.new(@editor.terminal.keys).parse_bytes_into_sequences(bytes)
      end

      #
      # Process a character. If the key corresponding to the inputted character
      # is bound to an action, call <tt>press_key</tt>, otherwise call <tt>default_action</tt>.
      # This method is called automatically by <tt>read</tt>
      #
      def process_character(byte_sequence)
        if byte_sequence.is_a?(Array)
          key_binding = key_binding_for_bytes(byte_sequence)
          key_binding.call(byte_sequence) if key_binding
        else
          default_action(byte_sequence)
        end
      end
    end
  end
end
