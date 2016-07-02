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

    def pause(&blk)
      @paused = true
    end

    def render(reset: false, &blk)
      Treefell['editor'].puts %|#{self.class}##{__callee__} reset=#{reset}}|
      if @paused
        Treefell['editor'].puts "    paused"
        if @render_on_unpause_kwargs && @render_on_unpause_kwargs[:reset]
          reset = true
        end
        @render_on_unpause_kwargs = {reset: reset}
      else
        Treefell['editor'].puts "    unpaused"
        @render_tree.layout
        @renderer.render(@render_tree, reset: reset)
      end
    end

    def render_cursor
      @renderer.render_cursor(@dom.focused_input_box)
    end

    def rollup(&blk)
      if block_given?
        begin
          pause
          blk.call
        ensure
          unpause
        end
      end
    end

    def update_dimensions(width:, height:)
      @render_tree.width = width
      @render_tree.height = height
    end

    def unpause
      @paused = false
      if @render_on_unpause_kwargs
        render(**@render_on_unpause_kwargs)
        @render_on_unpause_kwargs = nil
      end
    end
  end
end
