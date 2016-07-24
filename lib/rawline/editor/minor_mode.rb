module RawLine
  class Editor
    module MinorMode
      def self.included(base)
        base.extend self
      end

      def major_mode?
        false
      end

      def minor_mode?
        true
      end
    end
  end
end
