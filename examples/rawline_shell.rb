#!usr/bin/env ruby

require File.dirname(File.expand_path(__FILE__))+'/../lib/rawline'
require 'io/console'

require 'highline/system_extensions'
module HighLine::SystemExtensions
  def get_character( input = STDIN )
    input.raw do
      input.getbyte
    end
  end
end

puts "*** Rawline Editor Test Shell ***"
puts " * Press CTRL+X to exit"
puts " * Press CTRL+G to clear command history"
puts " * Press CTRL+D for line-related information"
puts " * Press CTRL+E to view command history"

editor = RawLine::Editor.new

editor.terminal.keys.merge!(enter: [13])
editor.bind(:return){ editor.newline }

editor.bind(:ctrl_g) { editor.clear_history }
editor.bind(:ctrl_l) { editor.debug_line }
editor.bind(:ctrl_h) { editor.show_history }
editor.bind(:ctrl_d) { puts; puts "Exiting..."; exit }
editor.bind(:ctrl_a) { editor.move_to_position 0 }
editor.bind(:ctrl_e) { editor.move_to_position editor.line.length }

editor.completion_proc = lambda do |word|
  if word
    ['select', 'update', 'delete', 'debug', 'destroy'].find_all  { |e| e.match(/^#{Regexp.escape(word)}/) }
  end
end

loop do
  puts "You typed: [#{editor.read("=> ", true)}]"
end
