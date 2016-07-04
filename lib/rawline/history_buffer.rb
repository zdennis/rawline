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
  class HistoryBuffer
    DefaultSize = 1024
    Infinity = 1.0 / 0

    # +size+ is used to determine how many history items should be kept.
    attr_reader :size

    # +duplicates+ is used to determine if the history can house duplicate \
    # items, consecutively
    attr_accessor :duplicates

    # +exclude+ can be set to a lambda/proc filter to determine
    # if an item should be excluded from the history
    attr_accessor :exclude

    # +cycle+ is used to determine if the the buffer is cyclic
    attr_accessor :cycle

    # +position+ can be used to set or get the current location of the history
    attr_accessor :position

    def self.new_with_infinite_size(**kwargs)
      new(Infinity, **kwargs)
    end

    #
    # Create an instance of RawLine::HistoryBuffer.
    # This method takes an optional block used to override the
    # following properties:
    #
    # * <tt>duplicates</tt> - whether or not duplicate items will be stored in the buffer.
    # * <tt>exclude</tt> - a Proc object defining exclusion rules to prevent items from being added to the buffer.
    # * <tt>cycle</tt> - Whether or not the buffer is cyclic.
    #
    def initialize(size=DefaultSize, cycle: false, duplicates: true, exclude: nil)
      @history = []
      @duplicates = duplicates
      @exclude = exclude || -> (item){ }
      @cycle = cycle
      yield self if block_given?
      @size = size && size > 0 ? size : DefaultSize
      @position = nil
    end

    def [](index)
      @history[index]
    end

    def any?(&blk)
      @history.any?(&blk)
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
        @position = length - 1
      when 0 then
        @position = length - 1 if @cycle
      else
        @position -= 1
      end
    end

    #
    # Clear the content of the buffer and resets <tt>position</tt> to nil.
    #
    def clear
      @position = nil
      @history.clear
    end

    #
    # Clears the current position on the history object. Useful when deciding
    # to cancel/reset history navigation.
    #
    def clear_position
      @position = nil
    end

    def detect(&blk)
      @history.detect(&blk)
    end

    def each(&blk)
      @history.each(&blk)
    end

    # Return true if the history is empty, otherwise false.
    def empty?
      @history.empty?
    end

    #
    # Return true if <tt>@position</tt> is at the end of the buffer.
    #
    def end?
      @position == length - 1
    end

    #
    # Override equals check. Will be the same as another HistoryBuffer
    # object with the same history items. Ignores position, exclusion filter,
    # and so on.
    #
    def ==(other)
      other.is_a?(self.class) &&
        other.instance_variable_get(:@history) == @history
    end

    #
    # Finds and returns the first item matching the given text, starting
    # from the current <tt>position</tt>, moving backwards. The given text
    # will be successfully matched if it matches any part of a history item.
    #
    def find_match_backward(text)
      regex = to_regex(text)
      @position = nil if @position == 0 && @cycle
      offset = @position ? length - position : 0
      @history.reverse[offset..-1].detect.with_index do |item, index|
        if item.match(regex)
          @position = length - index - (offset + 1)
        end
      end
    end

    #
    # Finds and returns the first item matching the given text, starting
    # from the current <tt>position</tt>, moving forwards. The given text
    # will be successfully matched if it matches any part of a history item.
    #
    def find_match_forward(text)
      regex = to_regex(text)
      @position = -1 if @position == length - 1 && @cycle
      offset = @position ? @position + 1 : 0
      @history[offset..-1].detect.with_index do |item, index|
        if item.match(regex)
          @position = index + offset
        end
      end
    end

    def first
      @history.first
    end

    def first!
      @position = 0
      get
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
        @position = length - 1
      when length-1 then
        @position = 0 if @cycle
      else
        @position += 1
      end
    end

    #
    # Retrieve a copy of the history item at the current <tt>position</tt>.
    #
    def get
      return nil unless length > 0
      @position = length - 1 unless @position
      @history.at(@position).dup
    end

    #
    # Returns the index of the given item if it exists in the history,
    # otherwise nil.
    #
    def index(item)
      @history.index(item)
    end

    #
    # Retrieve a copy of the last history item
    #
    def last
      return nil unless @history.last
      @history.last.dup
    end

    #
    # Returns the number of items in the HistoryBuffer.
    #
    def length
      @history.length
    end

    def map(&blk)
      @history.map(&blk)
    end

    #
    # Add a new item to the buffer.
    #
    def push(item)
      if !@duplicates && last == item
        # skip adding this line
        return self
      end

      unless @exclude.call(item)
        # Remove the oldest element if size is exceeded
        if @size <= length
          @history.reverse!.pop
          @history.reverse!
        end
        # Add the new item and reset the position
        @history.push item
        @position = nil
      end
      self
    end
    alias << push

    #
    # Replaces the current history with the given <tt>new_history</tt>. The
    # new_history can be given as an array of history items or a HistoryBuffer
    # object.
    def replace(new_history)
      if new_history.is_a?(HistoryBuffer)
        new_history = new_history.instance_variable_get(:@history)
      end
      @history.replace(new_history)
    end

    #
    # Resize the buffer, resetting <tt>position</tt> to nil.
    #
    def resize(new_size)
      if new_size < length
        (length - new_size).times { @history.shift }
      end
      @size = new_size
      @position = nil
      self
    end

    def reverse
      self.class.new(size).tap do |new_history|
        @history.reverse.each do |item|
          new_history << item
        end
      end
    end

    #
    # Return true if <tt>position</tt> is at the start of the buffer.
    #
    def beginning?
      @position == 0
    end

    #
    # Returns a copy of the HistoryBuffer as an array.
    #
    def to_a
      @history.dup
    end

    private

    def to_regex(text)
      return text if text.is_a?(Regexp)
      /#{Regexp.escape(text)}/
    end
  end

end
