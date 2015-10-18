#!usr/bin/env ruby

require 'io/console'
require 'ostruct'

#
#  terminal.rb
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
  # The Terminal class defines character codes and code sequences which can be
  # bound to actions by editors.
  # An OS-dependent subclass of RawLine::Terminal is automatically instantiated by
  # RawLine::Editor.
  #
  class Terminal

    include HighLine::SystemExtensions

    attr_accessor :escape_codes
    attr_reader :keys, :escape_sequences

    #
    # Create an instance of RawLine::Terminal.
    #
    def initialize
      @keys =
        {
        :tab => [?\t.ord],
        :return => [?\r.ord],
        :newline => [?\n.ord],
        :escape => [?\e.ord],

        :ctrl_a => [?\C-a.ord],
        :ctrl_b => [?\C-b.ord],
        :ctrl_c => [?\C-c.ord],
        :ctrl_d => [?\C-d.ord],
        :ctrl_e => [?\C-e.ord],
        :ctrl_f => [?\C-f.ord],
        :ctrl_g => [?\C-g.ord],
        :ctrl_h => [?\C-h.ord],
        :ctrl_i => [?\C-i.ord],
        :ctrl_j => [?\C-j.ord],
        :ctrl_k => [?\C-k.ord],
        :ctrl_l => [?\C-l.ord],
        :ctrl_m => [?\C-m.ord],
        :ctrl_n => [?\C-n.ord],
        :ctrl_o => [?\C-o.ord],
        :ctrl_p => [?\C-p.ord],
        :ctrl_q => [?\C-q.ord],
        :ctrl_r => [?\C-r.ord],
        :ctrl_s => [?\C-s.ord],
        :ctrl_t => [?\C-t.ord],
        :ctrl_u => [?\C-u.ord],
        :ctrl_v => [?\C-v.ord],
        :ctrl_w => [?\C-w.ord],
        :ctrl_x => [?\C-x.ord],
        :ctrl_y => [?\C-y.ord],
        :ctrl_z => [?\C-z.ord]
        }
      @escape_codes = []
      @escape_sequences = []
      update
    end

    CursorPosition = Struct.new(:column, :row)

    def cursor_position
      res = ''
      $stdin.raw do |stdin|
        $stdout << "\e[6n"
        $stdout.flush
        while (c = stdin.getc) != 'R'
          res << c if c
        end
      end
      m = res.match /(?<row>\d+);(?<column>\d+)/
      CursorPosition.new(Integer(m[:column]), Integer(m[:row]))
    end

    def clear_to_beginning_of_line
      term_info.control "el1"
    end

    def clear_screen
      term_info.control "clear"
    end

    def clear_screen_down
      term_info.control "ed"
    end

    def move_to_beginning_of_row
      move_to_column 0
    end

    def move_left
      move_left_n_characters 1
    end

    def move_left_n_characters(n)
      term_info.control "cub1"
    end

    def move_right_n_characters(n)
      term_info.control "cuf1"
    end

    def move_to_column_and_row(column, row)
      term_info.control "cup", column, row
    end

    def move_to_column(n)
      term_info.control "hpa", n
    end

    def move_up_n_rows(n)
      n.times { term_info.control "cuu1" }
    end

    def move_down_n_rows(n)
      n.times { term_info.control "cud1" }
    end

    def preserve_cursor(&blk)
      term_info.control "sc" # store cursor position
      blk.call
    ensure
      term_info.control "rc" # restore cursor position
    end

    #
    # Update the terminal escape sequences. This method is called automatically
    # by RawLine::Editor#bind().
    #
    def update
      @keys.each_value do |k|
        l = k.length
        if  l > 1 then
          @escape_sequences << k unless @escape_sequences.include? k
        end
      end
    end

    def term_info
      @term_info ||= TermInfo.new(ENV["TERM"], $stdout)
    end

  end


end
