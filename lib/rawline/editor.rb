#!/usr/bin/env ruby

#
#  editor.rb
#
# Created by Fabio Cevasco on 2008-03-01.
# Copyright (c) 2008 Fabio Cevasco. All rights reserved.
#
# This is Free Software.  See LICENSE for details.
#

require 'forwardable'
require 'terminal_layout'
require 'ansi_string'
require 'term/ansicolor'
require 'fcntl'

module RawLine

  #
  # The Editor class defines methods to:
  #
  # * Read characters from STDIN or any type of input
  # * Write characters to STDOUT or any type of output
  # * Bind keys to specific actions
  # * Perform line-related operations like moving, navigating through history, etc.
  #
  # Note that the following default key bindings are provided:
  #
  # * TAB: word completion defined via completion_proc
  # * LEFT/RIGHT ARROWS: cursor movement (left/right)
  # * UP/DOWN ARROWS: history navigation
  # * DEL: Delete character under cursor
  # * BACKSPACE: Delete character before cursor
  # * INSERT: Toggle insert/replace mode (default: insert)
  # * CTRL+K: Clear the whole line
  # * CTRL+Z: undo (unless already registered by the OS)
  # * CTRL+Y: redo (unless already registered by the OS)
  #
  class Editor
    extend Forwardable
    include HighLine::SystemExtensions

    attr_accessor :char
    attr_accessor :terminal, :mode
    attr_accessor :completion_proc, :line, :history
    attr_accessor :match_hidden_files
    attr_accessor :word_break_characters
    attr_accessor :dom

    # TODO: dom traversal for lookup rather than assignment
    attr_accessor :prompt_box, :input_box, :content_box, :focused_input_box

    def self.create(dom: nil, &blk)
      terminal = nil

      input = STDIN
      output = STDOUT

      case RUBY_PLATFORM
      when /mswin/i then
        terminal = WindowsTerminal.new(input, output)
        if RawLine.win32console? then
          win32_io = Win32::Console::ANSI::IO.new
        end
      else
        terminal = VT220Terminal.new(input, output)
      end

      dom ||= DomTree.new

      renderer = RawLine::Renderer.new(
        dom: dom,
        output: terminal.output,
        width: terminal.width,
        height: terminal.height
      )

      KeyBindings.default_terminal = terminal

      new(
        dom: dom,
        input: NonBlockingInput.new(input),
        renderer: renderer,
        terminal: terminal,
        &blk
      )
    end

    class Environment
      attr_accessor :keys, :completion_class, :history, :word_separator
      attr_accessor :keyboard_input_processors

      # * <tt>@history_size</tt> - the size of the editor history buffer (30).
      # * <tt>@keys</tt> - the keys (arrays of character codes) bound to specific actions.
      # * <tt>@line_history_size</tt> - the size of the editor line history buffer (50).
      def initialize(env: nil)
        @env = env
        @keys = KeyBindings.new
        @keyboard_input_processors = []

        @completion_class = Completer

        @line_history_size = 50
        @history_size = 30

        @history = HistoryBuffer.new(@history_size) do |h|
          h.duplicates = false;
          h.exclude = lambda { |item| item.strip == "" }
        end
      end

      def initialize_line(&blk)
        Line.new(@line_history_size) do |line|
          blk.call(line) if blk
        end
      end
    end

    #
    # Create an instance of RawLine::Editor which can be used
    # to read from input and perform line-editing operations.
    # This method takes an optional block used to override the
    # following instance attributes:
    # * <tt>@word_break_characters</tt> - a regex used for word separation, default inclues: " \t\n\"\\'`@$><=;|&{("
    # * <tt>@mode</tt> - The editor's character insertion mode (:insert).
    # * <tt>@completion_proc</tt> - a Proc object used to perform word completion.
    # * <tt>@terminal</tt> -  a RawLine::Terminal containing character key codes.
    #
    def initialize(dom:, input:, renderer:, terminal:)
      @dom = dom
      @input = input
      @renderer = renderer
      @terminal = terminal

      @env_stack = [Environment.new]

      @word_break_characters = " \t\n\"'@><=;|&{()}"
      @mode = :insert

      @completion_proc = filename_completion_proc

      @match_hidden_files = false
      set_default_keys
      @add_history = false
      push_keyboard_input_processor self
      yield self if block_given?
      update_word_separator
      @char = nil

      initialize_events
      initialize_line
    end

    attr_reader :dom, :event_loop, :input
    attr_reader :keyboard_input_processors

    def env ; @env_stack.last ; end
    def new_env ; Environment.new ; end
    def push_env(env) ; @env_stack.push env ; end
    def pop_env ; @env_stack.pop ; end
    def keyboard_input_processor ; env.keyboard_input_processors.last ; end
    def push_keyboard_input_processor(kip) ; env.keyboard_input_processors.push kip ; end
    def pop_keyboard_input_processor ; env.keyboard_input_processors.pop ; end

    def completion_class ; @env_stack.first.completion_class ; end
    def history ; @env_stack.first.history ; end
    def keys ; @env_stack.first.keys ; end

    #
    # Return the current RawLine version
    #
    def library_version
      "RawLine v#{RawLine::VERSION}"
    end

    def prompt
      @prompt
    end

    def prompt=(text)
      return if @line && @line.prompt == text
      @prompt = Prompt.new(text)
      Treefell['editor'].puts "prompt=#{prompt.inspect}"
      @dom.prompt_box.content = @prompt
    end

    def redraw_prompt
      Treefell['editor'].puts "redrawing prompt=#{prompt.inspect} reset=true"
      render(reset: true)
    end

    def terminal_width ; @terminal.width ; end
    def terminal_height ; @terminal.height ; end

    def content_box ; @dom.content_box ; end
    def focused_input_box ; @dom.focused_input_box ; end
    def input_box ; @dom.input_box ; end
    def prompt_box ; @dom.prompt_box ; end

    ############################################################################
    #
    #                                EVENTS
    #
    ############################################################################

    # Starts the editor event loop. Must be called before the editor
    # can be interacted with.
    def start
      @terminal.raw!
      at_exit { @terminal.cooked! }

      Signal.trap("SIGWINCH") do
        Treefell['editor'].puts "terminal-resized trap=SIGWINCH"
        @event_loop.add_event name: "terminal-resized", source: self
      end

      @event_registry.subscribe("terminal-resized") do
        width, height = terminal_width, terminal_height
        Treefell['editor'].puts "terminal-resizing width=#{width} height=#{height}"
        @renderer.update_dimensions(width: width, height: height)
        @event_loop.add_event name: "render", source: self
      end

      @event_loop.add_event name: "render", source: self
      @event_loop.start
    end

    # Subscribes to an event with the given block as a callback.
    def subscribe(*args, &blk)
      @event_registry.subscribe(*args, &blk)
    end

    # Returns the Editor's event loop.
    def events
      @event_loop
    end

    ############################################################################
    #
    #                               INPUT
    #
    ############################################################################

    def check_for_keyboard_input
      bytes = @input.read
      if bytes.any?
        keyboard_input_processor.read_bytes(bytes)
      end
      @event_loop.add_event name: 'check_for_keyboard_input', source: self
    end

    def read_bytes(bytes)
      return unless bytes.any?
      @renderer.pause

      Treefell['editor'].puts "read_bytes #{bytes.inspect}"
      old_position = @line.position

      key_code_sequences = parse_key_code_sequences(bytes)

      Treefell['editor'].puts "key code sequences: #{key_code_sequences.inspect}"
      key_code_sequences.each do |sequence|
        @char = sequence
        if @char == @terminal.keys[:enter] || !@char
          Treefell['editor'].puts "processing line: #{@line.text.inspect}"
          @renderer.pause
          process_line
        else
          process_character
          new_position = @line.position
        end
      end
    ensure
      @renderer.unpause
    end

    def process_line
      text_to_process = @line.text.without_ansi.dup

      @event_loop.add_event(name: "process_line", source: self) do
        add_to_history

        @terminal.snapshot_tty_attrs
        @terminal.pseudo_cooked!

        @terminal.move_to_beginning_of_row
        @terminal.puts
      end

      @event_loop.add_event(name: "line_read", source: self, payload: { line: text_to_process })
      @event_loop.add_event(name: "prepare_new_line", source: self) do
        reset_line
        move_to_beginning_of_input
      end
      @event_loop.add_event(name: "restore_tty_attrs", source: self) { @terminal.restore_tty_attrs }
      @event_loop.add_event(name: "render", source: self, payload: { reset: true })
    end

    #
    # Process a character. If the key corresponding to the inputted character
    # is bound to an action, call <tt>press_key</tt>, otherwise call <tt>default_action</tt>.
    # This method is called automatically by <tt>read</tt>
    #
    def process_character
      if @char.is_a?(Array)
        press_key if key_bound?
      else
        default_action
      end
    end

    #
    # Bind a key to an action specified via <tt>block</tt>.
    # <tt>key</tt> can be:
    #
    # * A Symbol identifying a character or character sequence defined for the current terminal
    # * A Fixnum identifying a character defined for the current terminal
    # * An Array identifying a character or character sequence defined for the current terminal
    # * A String identifying a character or character sequence, even if it is not defined for the current terminal
    # * An Hash identifying a character or character sequence, even if it is not defined for the current terminal
    #
    # If <tt>key</tt> is a hash, then:
    #
    # * It must contain only one key/value pair
    # * The key identifies the name of the character or character sequence
    # * The value identifies the code(s) corresponding to the character or character sequence
    # * The value can be a Fixnum, a String or an Array.
    #
    def bind(key, &block)
      keys.bind(key, &block)
    end

    def unbind(key)
      keys.unbind(key)
    end

    #
    # Return true if the last character read via <tt>read</tt> is bound to an action.
    #
    def key_bound?
      keys.bound?(@char)
    end

    #
    # Call the action bound to the last character read via <tt>read</tt>.
    # This method is called automatically by <tt>process_character</tt>.
    #
    def press_key
      keys[@char].call
    end

    #
    # Execute the default action for the last character read via <tt>read</tt>.
    # By default it prints the character to the screen via <tt>write</tt>.
    # This method is called automatically by <tt>process_character</tt>.
    #
    def default_action
      insert(@char)
    end

    #
    # Parse a key or key sequence into the corresponding codes.
    #
    def parse_key_code_sequences(bytes)
      KeycodeParser.new(@terminal.keys).parse_bytes_into_sequences(bytes)
    end

    #
    # Adds <tt>@line.text</tt> to the editor history. This action is
    # bound to the enter key by default.
    #
    def newline
      add_to_history
			history.clear_position
    end

    def on_read_line(&blk)
      @event_registry.subscribe :line_read, &blk
    end

    ############################################################################
    #
    #                            LINE EDITING
    #
    ############################################################################

    #
    # Clear the current line, i.e.
    # <tt>@line.text</tt> and <tt>@line.position</tt>.
    # This action is bound to ctrl+k by default.
    #
    def clear_line
      Treefell['editor'].puts "clear_line"
      add_to_line_history
      @line_editor.clear_line
      history.clear_position
    end

    def clear_screen
      Treefell['editor'].puts "clear_screen"
      @terminal.clear_screen
      render(reset: true)
    end

    #
    # Delete the character at the left of the cursor.
    # If <tt>no_line_hisytory</tt> is set to true, the deletion won't be
    # recorded in the line history.
    # This action is bound to the backspace key by default.
    #
    def delete_left_character(no_line_history=false)
      Treefell['editor'].puts "delete_left_character"
      if @line_editor.delete_left_character
        add_to_line_history unless no_line_history
        history.clear_position
      end
    end

    def delete_n_characters(number_of_characters_to_delete, no_line_history=false)
      Treefell['editor'].puts "delete_n_characters n=#{number_of_characters_to_delete}"
      if @line_editor.delete_n_characters(number_of_characters_to_delete)
        add_to_line_history unless no_line_history
        history.clear_position
      end
    end

    #
    # Delete the character under the cursor.
    # If <tt>no_line_hisytory</tt> is set to true, the deletion won't be
    # recorded in the line history.
    # This action is bound to the delete key by default.
    #
    def delete_character(no_line_history=false)
      Treefell['editor'].puts "delete_character"
      if @line_editor.delete_character
        add_to_line_history unless no_line_history
        history.clear_position
      end
    end

    def highlight_text_up_to(text, position)
      Treefell['editor'].puts "highlight_text_up_to text=#{text} position=#{position}"
      @line_editor.highlight_text_up_to(text, position)
    end

    #
    # Inserts a string at the current line position, shifting characters
    # to right if necessary.
    #
    def insert(string, add_to_line_history: true)
      Treefell['editor'].puts "insert string=#{string} add_to_line_history=#{add_to_line_history}"
      if @line_editor.insert(string)
        self.add_to_line_history if add_to_line_history
      end
    end

    def kill_forward
      Treefell['editor'].puts "kill_forward"
      @line_editor.kill_forward.tap do
        add_to_line_history(allow_empty: true)
        history.clear_position
      end
    end

    #
    # Write a string starting from the cursor position ovewriting any character
    # at the current position if necessary.
    #
    def write(string, add_to_line_history: true)
      Treefell['editor'].puts "write string=#{string}"
      if @line_editor.write(string)
        self.add_to_line_history if add_to_line_history
      end
    end

    def yank_forward(text)
      Treefell['editor'].puts "yank_forward"
      @line_editor.yank_forward(text).tap do
        add_to_line_history
        history.clear_position
      end
    end

    #
    # Move the cursor left (if possible) by printing a
    # backspace, updating <tt>@line.position</tt> accordingly.
    # This action is bound to the left arrow key by default.
    #
    def move_left
      Treefell['editor'].puts "move_left"
      @line_editor.move_left
    end

    #
    # Move the cursor right (if possible) by re-printing the
    # character at the right of the cursor, if any, and updating
    # <tt>@line.position</tt> accordingly.
    # This action is bound to the right arrow key by default.
    #
    def move_right
      Treefell['editor'].puts "move_right"
      @line_editor.move_right
    end

    def move_to_beginning_of_input
      Treefell['editor'].puts "move_to_beginning_of_input"
      @line_editor.move_to_beginning_of_input
    end

    def move_to_end_of_input
      Treefell['editor'].puts "move_to_end_of_input"
      @line_editor.move_to_end_of_input
    end

    #
    # Move the cursor to <tt>pos</tt>.
    #
    def move_to_position(pos)
      Treefell['editor'].puts "move_to_position position=#{pos}"
      rows_to_move = current_terminal_row - terminal_row_for_line_position(pos)
      if rows_to_move > 0
        # rows_to_move.times { @output.print @terminal.term_info.control_string("cuu1") }
        # @terminal.move_up_n_rows(rows_to_move)
      else
        # rows_to_move.abs.times { @output.print @terminal.term_info.control_string("cud1") }
        # @terminal.move_down_n_rows(rows_to_move.abs)
      end
      column = (@line.prompt.length + pos) % terminal_width
      # @output.print @terminal.term_info.control_string("hpa", column)
      # @terminal.move_to_column((@line.prompt.length + pos) % terminal_width)
      @line_editor.position = pos
    end

    #
    # Overwrite the current line (<tt>@line.text</tt>)
    # with <tt>new_line</tt>, and optionally reset the cursor position to
    # <tt>position</tt>.
    #
    def overwrite_line(new_line, position=nil, options={})
      Treefell['editor'].puts "overwrite_line new_line=#{new_line} position=#{position} options=#{options.inspect}"
      if @line_editor.overwrite_line(new_line, position, options)
        @event_loop.add_event name: "render", source: focused_input_box
      end
    end

    def reset_line
      Treefell['editor'].puts "reset_line"
      initialize_line
      render(reset: true)
    end

    #
    # Toggle the editor <tt>@mode</tt> to :replace or :insert (default).
    #
    def toggle_mode
      case @mode
      when :insert then @mode = :replace
      when :replace then @mode = :insert
      end
    end

    ############################################################################
    #
    #                            OUTPUT
    #
    ############################################################################

    #
    # Write to <tt>output</tt> and then immediately re-render.
    #
    def puts(*args)
      @terminal.puts(*args)
      render(reset: true)
    end

    ############################################################################
    #
    #                             COMPLETION
    #
    ############################################################################

    #
    # Complete the current word according to what returned by
    # <tt>@completion_proc</tt>. Characters can be appended to the
    # completed word via <tt>@completion_append_character</tt> and word
    # separators can be defined via <tt>@word_separator</tt>.
    #
    # This action is bound to the tab key by default, so the first
    # match is displayed the first time the user presses tab, and all
    # the possible messages will be displayed (cyclically) when tab is
    # pressed again.
    #
    def complete
      focused_input_box.cursor_off
      completer = completion_class.new(
        char: @char,
        line: @line,
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
        done: -> (*leftover_bytes){
          completion_done
          leftover_bytes = leftover_bytes.flatten
          pop_keyboard_input_processor
          if leftover_bytes.any?
            keyboard_input_processor.read_bytes(leftover_bytes)
          end
          focused_input_box.cursor_on
        },
        keys: terminal.keys
      )
      push_keyboard_input_processor(completer)
      completer.read_bytes(@char)
    end

    def completion_found(completion:, possible_completions:)
      Treefell['editor'].puts "word-completion-found: #{completion.inspect} possible_completions: #{possible_completions.inspect}"
      if @on_word_complete
        word = @line.word[:text]
        sub_word = @line.text[@line.word[:start]..@line.position-1] || ""
        @on_word_complete.call(name: "word-completion", payload: { sub_word: sub_word, word: word, completion: completion, possible_completions: possible_completions })
      end

      completion_selected(completion)
    end

    def completion_selected(completion)
      Treefell['editor'].puts "word-completion-selected #{completion.inspect}"
      move_to_position @line.word[:end]
      delete_n_characters(@line.word[:end] - @line.word[:start], true)
      write completion.to_s

      if @on_word_completion_selected
        Treefell['editor'].puts "word-completion-selected callback called with #{completioni}"
        @on_word_completion_selected.call(name: "word-completion-selected", payload: { completion: completion })
      end
    end

    def completion_not_found
      Treefell['editor'].puts 'word-completion-not-found'
      if @on_word_complete_no_match
        word = @line.word[:text]
        sub_word = @line.text[@line.word[:start]..@line.position-1] || ""
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

    def on_word_complete(&blk)
      Treefell['editor'].puts "setting on_word_complete callback"
      @on_word_complete = blk
    end

    def on_word_complete_no_match(&blk)
      Treefell['editor'].puts "setting on_word_complete_no_match callback"
      @on_word_complete_no_match = blk
    end

    def on_word_complete_done(&blk)
      Treefell['editor'].puts "setting on_word_complete_done callback"
      @on_word_complete_done = blk
    end

    def on_word_completion_selected(&blk)
      Treefell['editor'].puts "setting on_word_completion_selected callback"
      @on_word_completion_selected = blk
    end

    #
    # Complete file and directory names.
    # Hidden files and directories are matched only if <tt>@match_hidden_files</tt> is true.
    #
    def filename_completion_proc
      lambda do |word, _|
        dirs = @line.text.split('/')
          path = @line.text.match(/^\/|[a-zA-Z]:\//) ? "/" : Dir.pwd+"/"
        if dirs.length == 0 then # starting directory
          dir = path
        else
          dirs.delete(dirs.last) unless File.directory?(path+dirs.join('/'))
          dir = path+dirs.join('/')
        end
        Dir.entries(dir).select { |e| (e =~ /^\./ && @match_hidden_files && word == '') || (e =~ /^#{word}/ && e !~ /^\./) }
      end
    end

    ############################################################################
    #
    #                            HISTORY
    #
    ############################################################################

    #
    # Print the content of the editor history. Note that after
    # the message is displayed, the line text and position will be restored.
    #
    def show_history
      pos = @line.position
      text = @line.text
      max_index_width = history.length.to_s.length
      history.each_with_index do |item, i|
        @terminal.puts sprintf("%-#{max_index_width}d %s\n", i+1, item)
      end
      render(reset: true)
      overwrite_line(text, pos)
    end

    #
    # Clear the editor history.
    #
    def clear_history
      history.empty
    end

    #
    # Undo the last modification to the current line (<tt>@line.text</tt>).
    # This action is bound to ctrl+z by default.
    #
    def undo
      generic_history_back(@line.history) if @line.history.position == nil
      generic_history_back(@line.history)
    end

    #
    # Redo a previously-undone modification to the
    # current line (<tt>@line.text</tt>).
    # This action is bound to ctrl+y by default.
    #
    def redo
      generic_history_forward(@line.history)
    end

    #
    # Load the previous entry of the editor in place of the
    # current line (<tt>@line.text</tt>).
    # This action is bound to the up arrow key by default.
    #
    def history_back
      generic_history_back(history)
      add_to_line_history
    end

    #
    # Load the next entry of the editor history in place of the
    # current line (<tt>@line.text</tt>).
    # This action is bound to down arrow key by default.
    #
    def history_forward
      generic_history_forward(history)
      add_to_line_history
    end

    #
    # Add the current line (<tt>@line.text</tt>) to the
    # line history, to allow undo/redo
    # operations.
    #
    def add_to_line_history(allow_empty: false)
      if allow_empty || !@line.text.empty?
        Treefell['editor'].puts "add_to_line_history text=#{@line.text}"
        @line.history << @line.text.dup
      end
    end

    #
    # Add the current line (<tt>@line.text</tt>) to the editor history.
    #
    def add_to_history(allow_empty: false)
      if @add_history && (allow_empty || !@line.text.empty?)
        Treefell['editor'].puts "add_to_history text=#{@line.text}"
        history << @line.text.dup
      end
    end

    ############################################################################
    #
    #                            DEBUGGING
    #
    ############################################################################

    #
    # Print debug information about the current line. Note that after
    # the message is displayed, the line text and position will be restored.
    #
    def debug_line
      pos = @line.position
      text = @line.text
      word = @line.word
      # terminal.puts
      # terminal.puts "Text: [#{text}]"
      # terminal.puts "Length: #{@line.length}"
      # terminal.puts "Position: #{pos}"
      # terminal.puts "Character at Position: [#{text[pos].chr}] (#{text[pos]})" unless pos >= @line.length
      # terminal.puts "Current Word: [#{word[:text]}] (#{word[:start]} -- #{word[:end]})"
      clear_line
      overwrite_line(text, pos)
    end

    def focus_input_box(box)
      @dom.focus_input_box(box)
      @renderer.render_cursor
    end

    private

    def initialize_events
      @event_registry = Rawline::EventRegistry.new do |registry|
        registry.subscribe :default, -> (_) { self.check_for_keyboard_input }
        registry.subscribe :dom_tree_change, -> (_) { self.render }
      end
      @event_loop = Rawline::EventLoop.new(registry: @event_registry)

      @dom.on(:content_changed) do |*args|
        Treefell['editor'].puts 'DOM content changed, re-rendering'
        @event_loop.add_event name: "render"
      end

      @dom.on(:child_changed) do |*args|
        Treefell['editor'].puts 'DOM child changed, re-rendering'
        @event_loop.add_event name: "render"
      end

      @dom.on :position_changed do |*args|
        Treefell['editor'].puts 'DOM position changed, rendering cursor'
        @renderer.render
      end

      @dom.on :focus_changed do |*args|
        Treefell['editor'].puts 'DOM focused changed, re-rendering'
        @renderer.render
      end

      @event_registry.subscribe :render, -> (_) { render(reset: false) }
    end

    def render(reset: false)
      @renderer.render(reset: reset)
      @event_loop.add_event name: "check_for_keyboard_input"
    end

    def initialize_line
      focused_input_box.content = ""
      update_word_separator
      @add_history = true
      @line = env.initialize_line do |l|
        l.prompt = @dom.prompt_box.content
        l.word_separator = @word_separator
      end
      @line_editor = LineEditor.new(
        @line,
        sync_with: -> { focused_input_box }
      )
      add_to_line_history
      @allow_prompt_updates = true
    end

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

    def generic_history_back(history)
      unless history.empty?
        history.back
        Treefell['editor'].puts "generic_history_back position=#{history.position} history=#{history.to_a.inspect}"
        line = history.get
        return unless line

        cursor_position = nil
        overwrite_line(line, cursor_position, highlight_up_to: cursor_position)
      end
    end

    def generic_history_forward(history)
      if history.forward
        Treefell['editor'].puts "generic_history_back position=#{history.position} history=#{history.to_a.inspect}"
        line = history.get
        return unless line

        cursor_position = nil
        overwrite_line(line, cursor_position, highlight_up_to: cursor_position)
      end
    end

    def set_default_keys
      bind(:space) { insert(' ') }
      bind(:enter) { newline }
      bind(:tab) { complete }
      bind(:backspace) { delete_left_character }
      bind(:ctrl_c) { raise Interrupt }
      bind(:ctrl_k) { clear_line }
      bind(:ctrl_u) { undo }
      bind(:ctrl_r) { self.redo }
      bind(:left_arrow) { move_left }
      bind(:right_arrow) { move_right }
      bind(:up_arrow) { history_back }
      bind(:down_arrow) { history_forward }
      bind(:delete) { delete_character }
      bind(:insert) { toggle_mode }
    end

    def terminal_row_for_line_position(line_position)
      ((@line.prompt.length + line_position) / terminal_width.to_f).ceil
    end

    def current_terminal_row
      ((@line.position + @line.prompt.length + 1) / terminal_width.to_f).ceil
    end

    def number_of_terminal_rows
      ((@line.length + @line.prompt.length) / terminal_width.to_f).ceil
    end
  end

  if RawLine.ansi? then
    class Editor
      if RUBY_PLATFORM.match(/mswin/) && RawLine.win32console? then
        def escape(string)
          string.each_byte { |c| @win32_io.putc c }
        end
      else
        def escape(string)
          # @terminal.print string
        end
      end
    end
  end

end
