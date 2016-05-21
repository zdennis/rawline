module RawLine
  class LineEditor
    def initialize(line, sync_with: -> {})
      @line = line
      @sync_with_proc = sync_with
    end

    #
    # Clear the current line, i.e.
    # <tt>@line.text</tt> and <tt>@line.position</tt>.
    # This action is bound to ctrl+k by default.
    #
    def clear_line
      @line.text = ""
      @line.position = 0
      sync!
      true
    end

    #
    # Delete the character at the left of the cursor.
    # If <tt>no_line_hisytory</tt> is set to true, the deletion won't be
    # recorded in the line history.
    # This action is bound to the backspace key by default.
    #
    def delete_left_character
      if move_left then
        delete_character
        sync!
        return true
      end
      false
    end

    def delete_n_characters(number_of_characters_to_delete)
      number_of_characters_to_delete.times do |n|
        @line[@line.position] = ''
        @line.left
      end
      sync!
      true
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
        #remove character from line
        @line[@line.position] = ''
        sync!
        return true
      end
      false
    end

    def highlight_text_up_to(text, position)
      ANSIString.new("\e[1m#{text[0...position]}\e[0m#{text[position..-1]}")
    end

    #
    # Inserts a string at the current line position, shifting characters
    # to right if necessary.
    #
    def insert(string)
      return false if string.empty?
      @line.text.insert @line.position, string
      string.length.times { @line.right }
      sync!
      true
    end

    def kill_forward
      @line.text[@line.position..-1].tap do
        @line.text[@line.position..-1] = ANSIString.new("")
        sync!
      end
    end

    #
    # Write a string starting from the cursor position ovewriting any character
    # at the current position if necessary.
    #
    def write(string)
      if @line.eol?
        @line.text[@line.position] = string
      else
        @line.text << string
      end
      string.length.times { @line.right }
      sync!
      true
    end

    def yank_forward(text)
      @line.text[@line.position...@line.position] = text
      @line.position = @line.position + text.length
      sync!
      @line.text
    end

    #
    # Move the cursor left (if possible) by printing a
    # backspace, updating <tt>@line.position</tt> accordingly.
    # This action is bound to the left arrow key by default.
    #
    def move_left
      unless @line.bol? then
        @line.left
        sync!
        return true
      end
      false
    end

    def move_right
      unless @line.position > @line.eol then
        @line.right
        sync!
        return true
      end
      false
    end

    def move_to_beginning_of_input
      @line.position = @line.bol
      sync!
      true
    end

    def move_to_end_of_input
      @line.position = @line.length
      sync!
      true
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

      @line.position = position || new_line.length
      @line.text = new_line
      sync!
      true
    end

    def position=(position)
      @line.position = position
      sync!
    end

    def text
      @line.text
    end

    private

    def select_characters_from_cursor(offset=0)
      select_characters(:right, @line.length-@line.position, offset)
    end

    def select_characters(direction, n, offset=0)
      if direction == :right then
        @line.text[@line.position+offset..@line.position+offset+n]
      elsif direction == :left then
        @line.text[@line.position-offset-n..@line.position-offset]
      end
    end

    def sync!
      positionable_object = @sync_with_proc.call
      if positionable_object
        positionable_object.position = @line.position
        positionable_object.content = @line.text
      end
    end

  end
end
