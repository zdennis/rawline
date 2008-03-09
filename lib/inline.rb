#!/usr/local/bin/ruby -w

module InLine
	HOME = File.dirname(File.expand_path(__FILE__))
	class BindingException < Exception; end
end

require "rubygems"
require "highline"
require "#{InLine::HOME}/inline/terminal"
require "#{InLine::HOME}/inline/terminal/windows_terminal"
require "#{InLine::HOME}/inline/terminal/vt220_terminal"
require "#{InLine::HOME}/inline/history_buffer"
require "#{InLine::HOME}/inline/line"
require "#{InLine::HOME}/inline/editor"


