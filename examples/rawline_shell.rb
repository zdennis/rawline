#!usr/bin/env ruby

require File.dirname(File.expand_path(__FILE__))+'/../lib/rawline'
require 'io/console'
require 'term/ansicolor'

# puts "*** Rawline Editor Test Shell ***"
# puts " * Press CTRL+X to exit"
# puts " * Press CTRL+G to clear command history"
# puts " * Press CTRL+D for line-related information"
# puts " * Press CTRL+E to view command history"

editor = RawLine::Editor.create
kill_ring = []

editor.terminal.keys.merge!(enter: [13])
editor.bind(:return){ editor.newline }

# Move to beginning of line
editor.bind(:ctrl_a) { editor.move_to_beginning_of_input }

# Move to end of line
editor.bind(:ctrl_e) { editor.move_to_end_of_input }

# Move backward one word at a time
editor.bind(:ctrl_b) {
  text = editor.line.text[0...editor.line.position].reverse
  position = text.index(/\s+/, 1)
  position = position ? (text.length - position) : 0
  editor.move_to_position position
}

# Move forward one word at a time
editor.bind(:ctrl_f) {
  text = editor.line.text
  position = text.index(/\s+/, editor.line.position)
  position = position ? (position + 1) : text.length
  editor.move_to_position position
}

# Yank text from the kill ring and insert it at the cursor position
editor.bind(:ctrl_y){
  text = kill_ring[-1]
  if text
    editor.yank_forward text
  end
}

# Backwards delete one word
editor.bind(:ctrl_w){
  before_text =  editor.line.text[0...editor.line.position]
  after_text = editor.line.text[editor.line.position..-1]

  have_only_seen_whitespace = true
  position = 0

  before_text.reverse.each_char.with_index do |ch, i|
    if ch =~ /\s/ && !have_only_seen_whitespace
      position = before_text.length - i
      break
    else
      have_only_seen_whitespace = false
    end
  end

  killed_text = before_text[position...editor.line.position]
  kill_ring.push killed_text

  text = [before_text.slice(0, position), after_text].join
  editor.overwrite_line text
  editor.move_to_position position
}

# History forward, but if at the end of the history then give user a
# blank line rather than remain on the last command
editor.bind(:down_arrow) {
  if editor.history.searching? && !editor.history.end?
    editor.history_forward
  else
    editor.overwrite_line ""
  end
}
editor.bind(:up_arrow) { editor.history_back }

editor.bind(:enter) { editor.newline }
editor.bind(:tab) { editor.complete }
editor.bind(:backspace) { editor.delete_left_character }

# Delete to end of line from cursor position
editor.bind(:ctrl_k) {
  kill_ring.push editor.kill_forward
}

# Delete to beginning of line from cursor position
editor.bind(:ctrl_u) {
  kill_ring.push editor.line.text[0...editor.line.position]
  editor.overwrite_line editor.line.text[editor.line.position..-1]
  editor.move_to_position 0
}

# Forward delete a character, leaving the cursor in place
editor.bind("\e[3~") {
  before_text =  editor.line.text[0...editor.line.position]
  after_text = editor.line.text[(editor.line.position+1)..-1]
  text = [before_text, after_text].join
  position = editor.line.position
  editor.overwrite_line text
  editor.move_to_position position
}

editor.bind(:ctrl_l){
  editor.clear_screen
}

editor.bind(:ctrl_r) {
   editor.redo
}
editor.bind(:left_arrow) { editor.move_left }
editor.bind(:right_arrow) { editor.move_right }
editor.bind(:up_arrow) { editor.history_back }
editor.bind(:down_arrow) { editor.history_forward }
editor.bind(:delete) { editor.delete_character }
editor.bind(:insert) { editor.toggle_mode }

editor.bind(:ctrl_g) { editor.clear_history }
# editor.bind(:ctrl_l) { editor.debug_line }
editor.bind(:ctrl_h) { editor.show_history }
editor.bind(:ctrl_d) { puts; puts "Exiting..."; exit }

# character-search; wraps around as necessary
editor.bind(:ctrl_n) {
  line = editor.line
  text, start_position = line.text, line.position
  i, new_position = start_position, nil

  break_on_bytes = [editor.terminal.keys[:ctrl_c]].flatten
  byte = [editor.read_character].flatten.first

  unless break_on_bytes.include?(byte)
    loop do
      i += 1
      i = 0 if i >= text.length                                    # wrap-around to the beginning
      break if i == start_position                                 # back to where we started
      (editor.move_to_position(i) ; break) if text[i] == byte.chr  # found a match; move and break
    end
  end
}

editor.completion_proc = lambda do |word|
  if word
    ['select', 'settle', 'seinfeld', 'sediment', 'selective', 'update', 'delete', 'debug', 'destroy'].find_all  { |e| e.match(/^#{Regexp.escape(word)}/) }
  end
end

editor.on_word_complete do |event|
  sub_word = event[:payload][:sub_word]
  word = event[:payload][:word]
  actual_completion = event[:payload][:completion]
  possible_completions =  event[:payload][:possible_completions]

  editor.content_box.content = possible_completions.map do |completion|
    if completion == actual_completion
      Term::ANSIColor.negative(completion)
    else
      completion
    end
  end.join("  ")
end

editor.on_word_complete_no_match do |event|
  sub_word = event[:payload][:sub_word]
  word = event[:payload][:word]
  editor.content_box.content = "Failed to find a match to complete #{sub_word} portion of #{word}"
end

editor.on_read_line do |event|
  line = event[:payload][:line]
  puts "You typed: [#{line}]"
  editor.reset_line
end

editor.on_word_complete_done do |event|
  editor.content_box.content = ""
end

editor.start
