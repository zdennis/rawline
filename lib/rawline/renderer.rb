module RawLine
  class Renderer
    def initialize(dom:, output:, width:, height:)
      @dom = dom
      @output = output
      @renderer = TerminalLayout::TerminalRenderer.new(output: output)
      @render_tree = TerminalLayout::RenderTree.new(
        dom,
        parent: nil,
        style: { width: width, height: height },
        renderer: @renderer
      )
    end

    def render(reset: false)
      @render_tree.layout
      @renderer.render(@render_tree, reset: reset)
    end

    def render_cursor
      @renderer.render_cursor(@dom.focused_input_box)
    end

    def update_dimensions(width:, height:)
      @render_tree.width = width
      @render_tree.height = height
    end
  end
end
