module RawLine
  class Environment
    attr_accessor :keys, :completion_class, :history, :word_separator
    attr_accessor :key_bindings_fall_back_to_parent
    attr_accessor :keyboard_input_processors
    attr_accessor :parent_env
    attr_accessor :terminal

    # * <tt>@history_size</tt> - the size of the editor history buffer (30).
    # * <tt>@keys</tt> - the keys (arrays of character codes) bound to specific actions.
    # * <tt>@line_history_size</tt> - the size of the editor line history buffer (50).
    def initialize(env: nil, keyboard_input_processors: [], key_bindings_fall_back_to_parent: false, parent_env: nil, terminal: nil)
      @env = env
      @parent_env = parent_env
      terminal = parent_env.terminal if !terminal && @parent_env
      @keys = KeyBindings.new(terminal: terminal)
      @keyboard_input_processors = keyboard_input_processors

      @completion_class = Completer

      @line_history_size = 50
      @history_size = 30

      @history = HistoryBuffer.new(@history_size) do |h|
        h.duplicates = false;
        h.exclude = lambda { |item| item.strip == "" }
      end

      self.key_bindings_fall_back_to_parent = key_bindings_fall_back_to_parent      
    end

    def initialize_line(&blk)
      Line.new(@line_history_size) do |line|
        blk.call(line) if blk
      end
    end

    def bind(key, &blk)
      @keys.bind(key, &blk)
    end

    def unbind(key)
      @keys.unbind(key)
    end

    def key_bindings_fall_back_to_parent=(boolean)
      @key_bindings_fall_back_to_parent = boolean
      if @key_bindings_fall_back_to_parent && @parent_env
        @keyboard_input_processors = @parent_env.keyboard_input_processors.dup
      end
    end

    def key_binding_for_bytes(bytes)
      key_binding = keys[bytes]
      if !key_binding && @key_bindings_fall_back_to_parent && @parent_env
        key_binding || @parent_env.key_binding_for_bytes(bytes)
      else
        key_binding
      end
    end

    def key_bound?(bytes)
      key_binding_for_bytes[bytes] ? true : false
    end

    def keyboard_input_processor=(processor)
      @keyboard_input_processors.push processor
    end
  end
end
