module RawLine
  class Editor
    module MajorMode
      def self.included(base)
        base.extend self
      end

      def major_mode?
        true
      end

      def minor_mode?
        false
      end
    end
  end
end
