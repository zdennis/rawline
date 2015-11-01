#!usr/bin/env ruby

#
#  RawLine.rb
#
# Created by Fabio Cevasco on 2008-03-01.
# Copyright (c) 2008 Fabio Cevasco. All rights reserved.
#
# This is Free Software.  See LICENSE for details.
#

require "rubygems"

#
# The RawLine (or Rawline) module can be used in the same way
# as the Readline one.
#
module RawLine

  def self.rawline_version
    "0.3.2"
  end

  class BindingException < RuntimeError; end

  if RUBY_PLATFORM.match(/mswin/i) then
    begin
      require 'win32console'
      def self.win32console?; true; end
      def self.ansi?; true; end
    rescue Exception
      def self.win32console?; false; end
      def self.ansi?; false; end
    end
  else # Unix-like
    def self.ansi?; true; end
  end
end

# Adding Fixnum#ord for Ruby 1.8.6
class Fixnum;  def ord; self; end;  end unless Fixnum.method_defined? :ord

Rawline = RawLine

dir = File.dirname(File.expand_path(__FILE__))
require "highline"
require "#{dir}/rawline/terminal"
require "#{dir}/rawline/terminal/windows_terminal"
require "#{dir}/rawline/terminal/vt220_terminal"
require "#{dir}/rawline/history_buffer"
require "#{dir}/rawline/line"
require "#{dir}/rawline/prompt"
require "#{dir}/rawline/completer"
require "#{dir}/rawline/event_loop"
require "#{dir}/rawline/event_registry"
require "#{dir}/rawline/editor"

module RawLine
end
