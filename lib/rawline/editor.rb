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

    attr_accessor :char, :history_size, :line_history_size, :highlight_history_matching_text
    attr_accessor :terminal, :keys, :mode
    attr_accessor :completion_class, :completion_proc, :line, :history, :completion_append_string
    attr_accessor :match_hidden_files
    attr_accessor :word_break_characters
    attr_reader :output
    attr_accessor :dom

    # TODO: dom traversal for lookup rather than assignment
    attr_accessor :prompt_box, :input_box, :content_box

    #
    # Create an instance of RawLine::Editor which can be used
    # to read from input and perform line-editing operations.
    # This method takes an optional block used to override the
    # following instance attributes:
    # * <tt>@history_size</tt> - the size of the editor history buffer (30).
    # * <tt>@line_history_size</tt> - the size of the editor line history buffer (50).
    # * <tt>@keys</tt> - the keys (arrays of character codes) bound to specific actions.
    # * <tt>@word_break_characters</tt> - a regex used for word separation, default inclues: " \t\n\"\\'`@$><=;|&{("
    # * <tt>@mode</tt> - The editor's character insertion mode (:insert).
    # * <tt>@completion_proc</tt> - a Proc object used to perform word completion.
    # * <tt>@completion_append_string</tt> - a string to append to completed words ('').
    # * <tt>@terminal</tt> -  a RawLine::Terminal containing character key codes.
    #
    def initialize(input=STDIN, output=STDOUT)
      @input = input
      @output = output

      case RUBY_PLATFORM
      when /mswin/i then
        @terminal = WindowsTerminal.new
        if RawLine.win32console? then
          @win32_io = Win32::Console::ANSI::IO.new
        end
      else
        @terminal = VT220Terminal.new
      end
      @history_size = 30
      @line_history_size = 50
      @keys = {}
      @word_break_characters = " \t\n\"'@\$><=;|&{("
      @mode = :insert
      @completion_class = Completer
      @completion_proc = filename_completion_proc
      @completion_append_string = ''
      @match_hidden_files = false
      set_default_keys
      @add_history = false
      @highlight_history_matching_text = true
      @history = HistoryBuffer.new(@history_size) do |h|
        h.duplicates = false;
        h.exclude = lambda { |item| item.strip == "" }
      end
      @keyboard_input_processors = [self]
      yield self if block_given?
      update_word_separator
      @char = nil

      @event_registry = Rawline::EventRegistry.new do |registry|
        registry.subscribe :default, -> (_) { self.check_for_keyboard_input }
        registry.subscribe :dom_tree_change, -> (_) { self.render }
      end
      @event_loop = Rawline::EventLoop.new(registry: @event_registry)

      @dom ||= build_dom_tree
      @renderer ||= build_renderer

      initialize_line
    end

    attr_reader :dom

    def events
      @event_loop
    end

    #
    # Return the current RawLine version
    #
    def library_version
      "RawLine v#{RawLine.rawline_version}"
    end

    def prompt
      @line.prompt if @line
    end

    def prompt=(text)
      return if !@allow_prompt_updates || @line.nil? || @line.prompt == text
      @prompt_box.content = Prompt.new(text)
    end

    def initialize_line
      @input_box.content = ""
      update_word_separator
      @add_history = true #add_history
      @line = Line.new(@line_history_size) do |l|
        l.prompt = @prompt_box.content
        l.word_separator = @word_separator
      end
      add_to_line_history
      @allow_prompt_updates = true
    end

    def reset_line
      initialize_line
      render(reset: true)
    end

    def check_for_keyboard_input
      bytes = []
      begin
        file_descriptor_flags = @input.fcntl(Fcntl::F_GETFL, 0)
        loop do
          string = @input.read_nonblock(4096)
          bytes.concat string.bytes
        end
      rescue IO::WaitReadable
        # reset flags so O_NONBLOCK is turned off on the file descriptor
        # if it was turned on during the read_nonblock above
        retry if IO.select([@input], [], [], 0.01)

        @input.fcntl(Fcntl::F_SETFL, file_descriptor_flags)
        @keyboard_input_processors.last.read_bytes(bytes)

        @event_loop.add_event name: 'check_for_keyboard_input', source: self
      end
    end

    def read_bytes(bytes)
      return unless bytes.any?
      old_position = @line.position
      key_codes = parse_key_codes(bytes)
      key_codes.each do |key_code|
        @char = key_code
        process_character

        new_position = @line.position

        if !@ignore_position_change && new_position != old_position
          @matching_text = @line.text[0...@line.position]
        end

        @ignore_position_change = false
        if @char == @terminal.keys[:enter] || !@char
          @allow_prompt_updates = false
          move_to_beginning_of_input

          old_tty_attrs = Termios.tcgetattr(@input)
          new_tty_attrs = old_tty_attrs.dup

          new_tty_attrs.cflag |= Termios::BRKINT | Termios::ISTRIP | Termios::ICRNL | Termios::IXON
          new_tty_attrs.oflag |= Termios::OPOST
          new_tty_attrs.lflag |= Termios::ECHO | Termios::ECHOE | Termios::ECHOK | Termios::ECHONL | Termios::ICANON | Termios::ISIG | Termios::IEXTEN

          Termios::tcsetattr(@input, Termios::TCSANOW, new_tty_attrs)
          @output.puts

          @event_loop.add_event name: "line_read", source: self, payload: { line: @line.text.without_ansi.dup }
          @event_loop.add_event name: "reset_tty_attrs", source: self, payload: { fd: @input, tty_attrs: old_tty_attrs }
          @event_loop.add_event name: "render", source: self, payload: { reset: true }
        end
      end
    end

    def on_read_line(&blk)
      @event_registry.subscribe :line_read, &blk
      @event_registry.subscribe :reset_tty_attrs do |event|
        Termios::tcsetattr(event[:payload][:fd], Termios::TCSANOW, event[:payload][:tty_attrs])
      end
    end

    def start
      @input.raw!
      at_exit { @input.cooked! }

      Signal.trap("SIGWINCH") do
        @event_loop.add_event name: "terminal-resized", source: self
      end

      @event_registry.subscribe("terminal-resized") do
        @render_tree.width = terminal_width
        @render_tree.height = terminal_height
        @event_loop.add_event name: "render", source: self
      end

      @event_loop.add_event name: "render", source: self
      @event_loop.start
    end

    def subscribe(*args, &blk)
      @event_registry.subscribe(*args, &blk)
    end

    #
    # Parse a key or key sequence into the corresponding codes.
    #
    def parse_key_codes(bytes)
      KeycodeParser.new(@terminal.keys).parse_bytes(bytes)
    end

    #
    # Write to <tt>@output</tt> and then immediately re-render.
    #
    def puts(*args)
      @output.cooked do
        @output.puts(*args)
      end
      render
    end

    #
    # Write a string to <tt># @output</tt> starting from the cursor position.
    # Characters at the right of the cursor are shifted to the right if
    # <tt>@mode == :insert</tt>, deleted otherwise.
    #
    def append_to_input(string)
      @line.text[@line.position] = string
      string.length.times { @line.right }
      @input_box.position = @line.position
      @input_box.content = @line.text

      add_to_line_history
    end

    #
    # Process a character. If the key corresponding to the inputted character
    # is bound to an action, call <tt>press_key</tt>, otherwise call <tt>default_action</tt>.
    # This method is called automatically by <tt>read</tt>
    #
    def process_character
      case @char.class.to_s
      when 'Fixnum' then
        default_action
      when 'Array'
        press_key if key_bound?
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
      case key.class.to_s
      when 'Symbol' then
        raise BindingException, "Unknown key or key sequence '#{key.to_s}' (#{key.class.to_s})" unless @terminal.keys[key]
        @keys[@terminal.keys[key]] = block
      when 'Array' then
        raise BindingException, "Unknown key or key sequence '#{key.join(", ")}' (#{key.class.to_s})" unless @terminal.keys.has_value? key
        @keys[key] = block
      when 'Fixnum' then
        raise BindingException, "Unknown key or key sequence '#{key.to_s}' (#{key.class.to_s})" unless @terminal.keys.has_value? [key]
        @keys[[key]] = block
      when 'String' then
        if key.length == 1 then
          @keys[[key.ord]] = block
        else
          bind_hash({:"#{key}" => key}, block)
        end
      when 'Hash' then
        raise BindingException, "Cannot bind more than one key or key sequence at once" unless key.values.length == 1
        bind_hash(key, block)
      else
        raise BindingException, "Unable to bind '#{key.to_s}' (#{key.class.to_s})"
      end
      @terminal.update
    end

    #
    # Return true if the last character read via <tt>read</tt> is bound to an action.
    #
    def key_bound?
      @keys[@char] ? true : false
    end

    #
    # Call the action bound to the last character read via <tt>read</tt>.
    # This method is called automatically by <tt>process_character</tt>.
    #
    def press_key
      @keys[@char].call
    end

    #
    # Execute the default action for the last character read via <tt>read</tt>.
    # By default it prints the character to the screen via <tt>print_character</tt>.
    # This method is called automatically by <tt>process_character</tt>.
    #
    def default_action
      @input_box.content += @char.chr
      print_character
    end

    #
    # Write a character to <tt># @output</tt> at cursor position,
    # shifting characters as appropriate.
    # If <tt>no_line_history</tt> is set to <tt>true</tt>, the updated
    # won't be saved in the history of the current line.
    #
    def print_character(char=@char, no_line_history = false)
      if @line.position < @line.length then
        chars = select_characters_from_cursor if @mode == :insert
        @line.text[@line.position] = (@mode == :insert) ? "#{char.chr}#{@line.text[@line.position]}" : "#{char.chr}"
        @line.right
        @input_box.position = @line.position
        # if @mode == :insert then
        #   chars.length.times { @line.left } # move cursor back
        # end
      else
        @line.right
        @line << char
      end
      @input_box.content = @line.text
      @input_box.position = @line.position
      add_to_line_history unless no_line_history
    end

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
      @input_box.cursor_off
      completer = @completion_class.new(
        char: @char,
        line: @line,
        completion: @completion_proc,
        completion_found: -> (completion:, possible_completions:) {
          completion_found(completion: completion, possible_completions: possible_completions)
        },
        completion_not_found: -> {
          completion_not_found
        },
        done: -> (*leftover_bytes){
          completion_done
          leftover_bytes = leftover_bytes.flatten
          @keyboard_input_processors.pop
          if leftover_bytes.any?
            @keyboard_input_processors.last.read_bytes(leftover_bytes)
          end
          @input_box.cursor_on
        },
        keys: terminal.keys
      )
      @keyboard_input_processors.push(completer)
      completer.read_bytes(@char)
    end

    def completion_found(completion:, possible_completions:)
      if @on_word_complete
        word = @line.word[:text]
        sub_word = @line.text[@line.word[:start]..@line.position-1] || ""
        @on_word_complete.call(name: "word-completion", payload: { sub_word: sub_word, word: word, completion: completion, possible_completions: possible_completions })
      end

      move_to_position @line.word[:end]
      delete_n_characters(@line.word[:end] - @line.word[:start], true)
      append_to_input completion.to_s + @completion_append_string.to_s
    end

    def completion_not_found
      if @on_word_complete_no_match
        word = @line.word[:text]
        sub_word = @line.text[@line.word[:start]..@line.position-1] || ""
        @on_word_complete_no_match.call(name: "word-completion-no-match", payload: { sub_word: sub_word, word: word })
      end
    end

    def completion_done
      if @on_word_complete_done
        @on_word_complete_done.call
      end
    end

    def on_word_complete(&blk)
      @on_word_complete = blk
    end

    def on_word_complete_no_match(&blk)
      @on_word_complete_no_match = blk
    end

    def on_word_complete_done(&blk)
      @on_word_complete_done = blk
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


    #
    # Adds <tt>@line.text</tt> to the editor history. This action is
    # bound to the enter key by default.
    #
    def newline
      add_to_history
			@history.clear_position
    end

    #
    # Move the cursor left (if possible) by printing a
    # backspace, updating <tt>@line.position</tt> accordingly.
    # This action is bound to the left arrow key by default.
    #
    def move_left
      unless @line.bol? then
        @line.left
        @input_box.position = @line.position
        return true
      end
      false
    end

    #
    # Move the cursor right (if possible) by re-printing the
    # character at the right of the cursor, if any, and updating
    # <tt>@line.position</tt> accordingly.
    # This action is bound to the right arrow key by default.
    #
    def move_right
      unless @line.position > @line.eol then
        @line.right
        @input_box.position = @line.position
        return true
      end
      false
    end

    #
    # Print debug information about the current line. Note that after
    # the message is displayed, the line text and position will be restored.
    #
    def debug_line
      pos = @line.position
      text = @line.text
      word = @line.word
      # @output.puts
      # @output.puts "Text: [#{text}]"
      # @output.puts "Length: #{@line.length}"
      # @output.puts "Position: #{pos}"
      # @output.puts "Character at Position: [#{text[pos].chr}] (#{text[pos]})" unless pos >= @line.length
      # @output.puts "Current Word: [#{word[:text]}] (#{word[:start]} -- #{word[:end]})"
      clear_line
      raw_print text
      overwrite_line(text, pos)
    end

    #
    # Print the content of the editor history. Note that after
    # the message is displayed, the line text and position will be restored.
    #
    def show_history
      pos = @line.position
      text = @line.text
      # @output.puts
      # @output.puts "History:"
      @history.each {|l| puts "- [#{l}]"}
      overwrite_line(text, pos)
    end

    #
    # Clear the editor history.
    #
    def clear_history
      @history.empty
    end

    #
    # Delete the character at the left of the cursor.
    # If <tt>no_line_hisytory</tt> is set to true, the deletion won't be
    # recorded in the line history.
    # This action is bound to the backspace key by default.
    #
    def delete_left_character(no_line_history=false)
      if move_left then
        delete_character(no_line_history)
      end
    end

    def delete_n_characters(number_of_characters_to_delete, no_line_history=false)
      if @line.position > @line.eol
        @line.position = @line.eol
      end

      number_of_characters_to_delete.times do |n|
        @line[@line.position] = ''
        @line.left
      end

      @input_box.position = @line.position
      @input_box.content = @line.text
      add_to_line_history unless no_line_history
      @history.clear_position
    end

    #
    # Delete the character under the cursor.
    # If <tt>no_line_hisytory</tt> is set to true, the deletion won't be
    # recorded in the line history.
    # This action is bound to the delete key by default.
    #
    def delete_character(no_line_history=false)
      unless @line.position > @line.eol
        # save characters to shift
        chars = (@line.eol?) ? ' ' : select_characters_from_cursor(1)
        # remove character from console and shift characters
        # (chars.length+1).times { # @output.putc ?\b.ord }
        #remove character from line
        @line[@line.position] = ''
        @input_box.content = @line.text
        @input_box.position = @line.position
        add_to_line_history unless no_line_history
        @history.clear_position
      end
    end

    #
    # Clear the current line, i.e.
    # <tt>@line.text</tt> and <tt>@line.position</tt>.
    # This action is bound to ctrl+k by default.
    #
    def clear_line
      # @output.putc ?\r
      # @output.print @line.prompt
      # @line.length.times {  @output.putc ?\s.ord }
      # @line.length.times {  @output.putc ?\b.ord }
      add_to_line_history
      @line.text = ""
      @line.position = 0
      @input_box.position = @line.position
      @history.clear_position
    end

    def clear_screen
      # @output.print @terminal.term_info.control_string("clear")
      # @terminal.clear_screen
      # @output.print @line.prompt
      # @output.print @line.text
      # (@line.length - @line.position).times {  @output.putc ?\b.ord }
    end

    def clear_screen_down
      # @output.print @terminal.term_info.control_string("ed")
      # @terminal.clear_screen_down
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
      generic_history_back(@history)
      add_to_line_history
    end

    #
    # Load the next entry of the editor history in place of the
    # current line (<tt>@line.text</tt>).
    # This action is bound to down arrow key by default.
    #
    def history_forward
      generic_history_forward(@history)
      add_to_line_history
    end

    #
    # Add the current line (<tt>@line.text</tt>) to the
    # line history, to allow undo/redo
    # operations.
    #
    def add_to_line_history
      @line.history << @line.text.dup unless @line.text == ""
    end

    #
    # Add the current line (<tt>@line.text</tt>) to the editor history.
    #
    def add_to_history
      @history << @line.text.dup if @add_history && @line.text != ""
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

    def terminal_row_for_line_position(line_position)
      ((@line.prompt.length + line_position) / terminal_width.to_f).ceil
    end

    def current_terminal_row
      ((@line.position + @line.prompt.length + 1) / terminal_width.to_f).ceil
    end

    def number_of_terminal_rows
      ((@line.length + @line.prompt.length) / terminal_width.to_f).ceil
    end

    def kill_forward
      @line.text[@line.position..-1].tap do
        @line.text = ANSIString.new("")
        @input_box.content = line.text
        @input_box.position = @line.position
        @history.clear_position
      end
    end

    def yank_forward(text)
      @line.text[line.position] = text
      @line.position = line.position + text.length
      @input_box.content = line.text
      @input_box.position = @line.position
      @history.clear_position
    end

    #
    # Overwrite the current line (<tt>@line.text</tt>)
    # with <tt>new_line</tt>, and optionally reset the cursor position to
    # <tt>position</tt>.
    #
    def overwrite_line(new_line, position=nil, options={})
      text = @line.text
      @highlighting = false

      if options[:highlight_up_to]
        @highlighting = true
        new_line = highlight_text_up_to(new_line, options[:highlight_up_to])
      end

      @ignore_position_change = true
      @line.position = new_line.length
      @line.text = new_line
      @input_box.content = @line.text
      @input_box.position = @line.position
      @event_loop.add_event name: "render", source: @input_box
    end

    def highlight_text_up_to(text, position)
      ANSIString.new("\e[1m#{text[0...position]}\e[0m#{text[position..-1]}")
    end

    def move_to_beginning_of_input
      @line.position = @line.bol
      @input_box.position = @line.position
    end

    def move_to_end_of_input
      @line.position = @line.length
      @input_box.position = @line.position
    end

    #
    # Move the cursor to <tt>pos</tt>.
    #
    def move_to_position(pos)
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
      @line.position = pos
      @input_box.position = @line.position
    end

    def move_to_end_of_line
      rows_to_move_down = number_of_terminal_rows - current_terminal_row
      # rows_to_move_down.times { @output.print @terminal.term_info.control_string("cud1") }
      # @terminal.move_down_n_rows rows_to_move_down
      @line.position = @line.length
      @input_box.position = @line.position

      column = (@line.prompt.length + @line.position) % terminal_width
      # @output.print @terminal.term_info.control_string("hpa", column)
      # @terminal.move_to_column((@line.prompt.length + @line.position) % terminal_width)
    end

    def move_up_n_lines(n)
      # n.times { @output.print @terminal.term_info.control_string("cuu1") }
      # @terminal.move_up_n_rows(n)
    end

    def move_down_n_lines(n)
      # n.times { @output.print @terminal.term_info.control_string("cud1") }
      # @terminal.move_down_n_rows(n)
    end

    def redraw_prompt
      render(reset: true)
    end

    private

    def build_dom_tree
      @prompt_box = TerminalLayout::Box.new(content: "default-prompt>", style: {display: :inline})
      @input_box = TerminalLayout::InputBox.new(content: "", style: {display: :inline})
      @content_box = TerminalLayout::Box.new(content: "", style: {display: :block})
      TerminalLayout::Box.new(children:[@prompt_box, @input_box, @content_box])
    end

    def build_renderer
      @renderer = TerminalLayout::TerminalRenderer.new(output: @output)
      @render_tree = TerminalLayout::RenderTree.new(
        @dom,
        parent: nil,
        style: { width:terminal_width, height:terminal_height },
        renderer: @renderer
      )

      @dom.on(:child_changed) do |*args|
        @event_loop.add_event name: "render", source: @dom#, target: event[:target]
      end

      @dom.on :cursor_position_changed do |*args|
        @renderer.render_cursor(@input_box)
      end

      @event_registry.subscribe :render, -> (_) { render(reset: false) }

      @renderer
    end

    def render(reset: false)
      @render_tree.layout
      @renderer.reset if reset
      @renderer.render(@render_tree)
      @event_loop.add_event name: "check_for_keyboard_input"
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

    def bind_hash(key, block)
      key.each_pair do |j,k|
        raise BindingException, "'#{k[0].chr}' is not a legal escape code for '#{@terminal.class.to_s}'." unless k.length > 1 && @terminal.escape_codes.include?(k[0].ord)
        code = []
        case k.class.to_s
        when 'Fixnum' then
          code = [k]
        when 'String' then
          k.each_byte { |b| code << b }
        when 'Array' then
          code = k
        else
          raise BindingException, "Unable to bind '#{k.to_s}' (#{k.class.to_s})"
        end
        @terminal.keys[j] = code
        @keys[code] = block
      end
    end

    def select_characters_from_cursor(offset=0)
      select_characters(:right, @line.length-@line.position, offset)
    end

    def raw_print(string)
      # string.each_byte { |c| @output.putc c }
    end

    def generic_history_back(history)
      unless history.empty?
        history.back(matching_text: matching_text)
        line = history.get
        return unless line

        cursor_position = nil
        if supports_partial_text_matching? && highlight_history_matching_text
          if line && matching_text
            cursor_position = [line.length, matching_text.length].min
          elsif matching_text
            cursor_position = matching_text.length
          end
        end

        overwrite_line(line, cursor_position, highlight_up_to: cursor_position)
      end
    end

    def supports_partial_text_matching?
      history.supports_partial_text_matching?
    end

    def generic_history_forward(history)
      if history.forward(matching_text: matching_text)
        line = history.get
        return unless line

        cursor_position = if supports_partial_text_matching? && highlight_history_matching_text && matching_text
          [line.length, matching_text.length].min
        end

        overwrite_line(line, cursor_position, highlight_up_to: cursor_position)
      end
    end

    def select_characters(direction, n, offset=0)
      if direction == :right then
        @line.text[@line.position+offset..@line.position+offset+n]
      elsif direction == :left then
        @line.text[@line.position-offset-n..@line.position-offset]
      end
    end

    def set_default_keys
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

    def matching_text
      return nil unless @line
      return nil if @line.text == ""
      if @history.searching?
        @matching_text
      else
        @matching_text = @line[0...@line.position]
      end
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
          # @output.print string
        end
      end

      def terminal_width
        terminal_size[0]
      end

      def terminal_height
        terminal_size[1]
      end

      def cursor_position
        terminal.cursor_position
      end
    end
  end

end
