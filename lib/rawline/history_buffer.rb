#!usr/bin/env ruby

#
#  history_buffer.rb
#
# Created by Fabio Cevasco on 2008-03-01.
# Copyright (c) 2008 Fabio Cevasco. All rights reserved.
#
# This is Free Software.  See LICENSE for details.
#
#
#
module RawLine

  #
  # The HistoryBuffer class is used to hold the editor and line histories, as well
  # as word completion matches.
  #
  class HistoryBuffer < Array

    attr_reader :position, :size
    attr_accessor :duplicates, :exclude, :cycle
    attr_accessor :matching_text

    #
    # Create an instance of RawLine::HistoryBuffer.
    # This method takes an optional block used to override the
    # following instance attributes:
    # * <tt>@duplicates</tt> - whether or not duplicate items will be stored in the buffer.
    # * <tt>@exclude</tt> - a Proc object defining exclusion rules to prevent items from being added to the buffer.
    # * <tt>@cycle</tt> - Whether or not the buffer is cyclic.
    #
    def initialize(size)
      @duplicates = true
      @exclude = lambda{|a|}
      @cycle = false
      yield self if block_given?
      @size = size
      @position = nil
    end

    def matching_text=(text)
      @matching_text = text

      # reset the current position
      @position = nil
    end

    def reset_search
      @matching_text = nil
      @position = nil
    end

    #
    # Resize the buffer, resetting <tt>@position</tt> to nil.
    #
    def resize(new_size)
      if new_size < @size
        @size-new_size.times { pop }
      end
      @size = new_size
      @position = nil
    end

    #
    # Clear the content of the buffer and reset <tt>@position</tt> to nil.
    #
    def empty
      @position = nil
      clear
    end

    #
    # Retrieve a copy of the element at <tt>@position</tt>.
    #
    def get
      return nil unless length > 0
      return nil unless @position
      at(@position).dup
    end

    #
    # Return true if <tt>@position</tt> is at the end of the buffer.
    #
    def end?
      @position == length-1
    end

    #
    # Return true if <tt>@position</tt> is at the start of the buffer.
    #
    def start?
      @position == 0
    end

    def find_position_backward_in_history(matching_text)
      index = (@position || length) - 1
      return @position unless index >= 0

      snapshot = self[0..index].dup.reverse
      no_match = nil

      position = snapshot.each_with_index.reduce(no_match) do |no_match, (text, i)|
        if text =~ /^#{Regexp.escape(matching_text)}/
          # convert to non-reversed indexing
          position = snapshot.length - (i + 1)
          break position
        else
          no_match
        end
      end
    end

    def find_position_forward_in_history(matching_text)
      $z.puts caller
      return nil unless @position

      index = @position + 1
      snapshot = self[index..-1].dup
      no_match = nil

      position = snapshot.each_with_index.reduce(no_match) do |no_match, (text, i)|
        if text =~ /^#{Regexp.escape(matching_text)}/
          position = index + i
          break position
        else
          no_match
        end
      end
    end

    #
    # Decrement <tt>@position</tt>.
    #
    def back
      return nil unless length > 0
      if matching_text
        @position = find_position_backward_in_history(matching_text) || @position
      else
        case @position
        when nil then
          @position = length-1
        when 0 then
          @position = length-1 if @cycle
        else
          @position -= 1
        end
      end
    end

    #
    # Increment <tt>@position</tt>.
    #
    def forward
      return nil unless length > 0
      if matching_text
        @position = find_position_forward_in_history(matching_text) || @position
        true
      else
        case @position
        when nil then
          nil
        when length-1 then
          @position = 0 if @cycle
        else
          @position += 1
        end
      end
    end

    #
    # Add a new item to the buffer.
    #
    def push(item)

      if !@duplicates && self[-1] == item
        # skip adding this line
        return
      end

      unless @exclude.call(item)
        # Remove the oldest element if size is exceeded
        if @size <= length
          reverse!.pop
          reverse!
        end
        # Add the new item and reset the position
        super(item)
        @position = nil
      end
    end

    alias << push

  end

end
