module RawLine
  class Renderer
    def initialize(dom:, output:, width:, height:)
      @dom = dom
      @output = output
      @paused = false
      @paused_attempts = []
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

    def paused?
      @paused
    end

    def render(reset: false, &blk)
      if @paused
        @paused_attempts << [:render, { reset: reset }]
      else
        Treefell['render'].puts %|\nRenderer:#{self.class}##{__callee__} reset=#{reset} caller=#{caller[0..5].join("\n")}}|
        @render_tree.layout
        @renderer.render(@render_tree, reset: reset)
      end
    end

    def render_cursor
      if @paused
        @paused_attempts << [:render_cursor, {}]
      else
        @renderer.render_cursor(@dom.focused_input_box)
      end
    end

    def rollup(&blk)
      if block_given?
        begin
          pause
          blk.call
        ensure
          unpause
          rollup_render_paused_attempts
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

    private

    def rollup_render_paused_attempts
      render_attempts = @paused_attempts.select do |attempt|
        attempt.first == :render
      end

      # rendering handles render_cursor so only explicitly rerender the
      # cursor if there were no render attempts
      if render_attempts.any?
        reset = render_attempts.any?{ |attempt| attempt.last[:reset] }
        render reset: reset
      else
        if @paused_attempts.any? { |attempt| attempt.first == :render_cursor }
          render_cursor
        end
      end
    ensure
      @paused_attempts.clear
    end
  end
end
