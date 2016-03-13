require 'terminal_layout'

module RawLine
  class DomTree < TerminalLayout::Box
    attr_accessor :prompt_box, :input_box, :content_box

    def initialize(children: nil)
      unless children
        @prompt_box = TerminalLayout::Box.new(content: "default-prompt>", style: {display: :inline})
        @input_box = TerminalLayout::InputBox.new(content: "", style: {display: :inline})
        @content_box = TerminalLayout::Box.new(content: "", style: {display: :block})
        super(style: {}, children: [@prompt_box, @input_box, @content_box])
      else
        super(style: {}, children: children)
      end
    end
  end
end
