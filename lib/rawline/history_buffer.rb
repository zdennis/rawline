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

    #
    # Clears the current position on the history object. Useful when deciding
    # to cancel/reset history navigation.
    #
    def clear_position
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

    def find_match_backward(text)
      regex = to_regex(text)
      offset = @position ? length - position : 0
      reverse[offset..-1].detect.with_index do |item, index|
        if item.match(regex)
          @position = length - index - (offset + 1)
        end
      end
    end

    def find_match_forward(text)
      regex = to_regex(text)
      offset = @position ? @position + 1 : 0
      self[offset..-1].detect.with_index do |item, index|
        if item.match(regex)
          @position = index + offset
        end
      end
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

    #
    # Decrement <tt>@position</tt>. By default the history will become
    # positioned at the previous item.
    #
    # If <tt>@cycle</tt> is set to true then the history will cycle to the end
    # when it finds itself at the beginning. If false calling this when
    # at the beginning will result in the position not changing.
    #
    # If a search strategy is assigned then the method <tt>search_backward</tt> will be
    # called on the search strategy to determine the position. This method is
    # given any passed in <tt>options</tt> as well as a <tt>:history</tt> option. The
    # <tt>:history</tt> option will be a reference to self.
    #
    def back(options={})
      return nil unless length > 0

      case @position
      when nil then
        @position = length-1
      when 0 then
        @position = length-1 if @cycle
      else
        @position -= 1
      end
    end

    #
    # Increment <tt>@position</tt>. By default the history will become
    # positioned at the next item.
    #
    # If <tt>@cycle</tt> is set to true then the history will cycle back to the
    # beginning when it finds itself at the end. If false calling this when
    # at the end will result in the position not changing.
    #
    # If a search strategy is assigned then the method <tt>search_forward</tt> will be
    # called on the search strategy to determine the position. This method is
    # given any passed in <tt>options</tt> as well as a <tt>:history</tt> option. The
    # <tt>:history</tt> option will be a reference to self. If <tt>
    #
    def forward(options={})
      return nil unless length > 0

      case @position
      when nil then
        @position = 0
      when length-1 then
        @position = 0 if @cycle
      else
        @position += 1
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

    private

    def to_regex(text)
      return text if text.is_a?(Regexp)
      /#{Regexp.escape(text)}/
    end
  end

end
