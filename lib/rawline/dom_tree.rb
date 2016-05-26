require 'terminal_layout'

module RawLine
  class DomTree < TerminalLayout::Box
    attr_accessor :prompt_box, :input_box, :content_box

    attr_accessor :focused_input_box

    def initialize(children: nil)
      unless children
        @prompt_box = TerminalLayout::Box.new(content: "default-prompt>", style: {display: :inline})
        @input_box = TerminalLayout::InputBox.new(content: "", style: {display: :inline})
        @content_box = TerminalLayout::Box.new(content: "", style: {display: :block})
        super(style: {}, children: [@prompt_box, @input_box, @content_box])
      else
        super(style: {}, children: children)
        @input_box = find_child_of_type(TerminalLayout::InputBox)
      end
      focus_input_box(@input_box)
    end

    def focus_input_box(box)
      @focused_input_box.remove_focus! if @focused_input_box
      @focused_input_box = box
      @focused_input_box.focus! if @focused_input_box
    end

    def input_box=(box)
      @input_box = box
      focus_input_box(@input_box)
    end
  end
end
