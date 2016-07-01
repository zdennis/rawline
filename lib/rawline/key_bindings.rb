module RawLine
  class KeyBindings
    attr_reader :keys

    class << self
      attr_accessor :default_terminal
    end

    def initialize(terminal: nil)
      @terminal = terminal || self.class.default_terminal
      @keys = {}
    end

    def [](char)
      keys[char]
    end

    #
    # Bind a key to an action specified via <tt>block</tt>.
    # <tt>key</tt> can be:
    #
    # * A Symbol identifying a character or character sequence defined for the current terminal
    # * A Fixnum identifying a character defined for the current terminal
    # * An Array identifying a character or character sequence defined for the current terminal
    # * A String identifying a character or character sequence, even if it is not defined for the current terminal
    # * An Hash identifying a character or character sequence, even if it is not defined for the current terminal
    #
    # If <tt>key</tt> is a hash, then:
    #
    # * It must contain only one key/value pair
    # * The key identifies the name of the character or character sequence
    # * The value identifies the code(s) corresponding to the character or character sequence
    # * The value can be a Fixnum, a String or an Array.
    #
    def bind(key, &block)
      case key.class.to_s
      when 'Symbol' then
        raise BindingException, "Unknown key or key sequence '#{key.to_s}' (#{key.class.to_s})" unless @terminal.keys[key]
        keys[@terminal.keys[key]] = block
      when 'Array' then
        raise BindingException, "Unknown key or key sequence '#{key.join(", ")}' (#{key.class.to_s})" unless @terminal.keys.has_value? key
        keys[key] = block
      when 'Fixnum' then
        raise BindingException, "Unknown key or key sequence '#{key.to_s}' (#{key.class.to_s})" unless @terminal.keys.has_value? [key]
        keys[[key]] = block
      when 'String' then
        if key.length == 1 then
          keys[[key.ord]] = block
        else
          bind_hash({:"#{key}" => key}, block)
        end
      when 'Hash' then
        raise BindingException, "Cannot bind more than one key or key sequence at once" unless key.values.length == 1
        bind_hash(key, block)
      else
        raise BindingException, "Unable to bind '#{key.to_s}' (#{key.class.to_s})"
      end
      @terminal.update
    end

    def bound?(char)
      keys[char] ? true : false
    end

    def unbind(key)
      block = case key.class.to_s
        when 'Symbol' then
          keys.delete @terminal.keys[key]
        when 'Array' then
          keys.delete keys[key]
        when 'Fixnum' then
          keys.delete[[key]]
        when 'String' then
          if key.length == 1 then
            keys.delete([key.ord])
          else
            raise NotImplementedError, "This is no implemented yet. It needs to return the previously bound block"
            bind_hash({:"#{key}" => key}, block)
          end
        when 'Hash' then
          raise BindingException, "Cannot bind more than one key or key sequence at once" unless key.values.length == 1
          bind_hash(key, -> { })
        end
      @terminal.update
      block
    end

    private

    def bind_hash(key, block)
      key.each_pair do |j,k|
        raise BindingException, "'#{k[0].chr}' is not a legal escape code for '#{@terminal.class.to_s}'." unless k.length > 1 && @terminal.escape_codes.include?(k[0].ord)
        code = []
        case k.class.to_s
        when 'Fixnum' then
          code = [k]
        when 'String' then
          k.each_byte { |b| code << b }
        when 'Array' then
          code = k
        else
          raise BindingException, "Unable to bind '#{k.to_s}' (#{k.class.to_s})"
        end
        @terminal.keys[j] = code
        keys[code] = block
      end
    end
  end
end
