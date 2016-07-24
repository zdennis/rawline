require 'rawline/mode/normal_mode'

module RawLine
  module Modes
    module ModeInterface
      attr_accessor :major

      def major?
        !!major
      end

      def minor?
        !major?
      end
    end

    module IsMajorMode
      def self.include(base)
        base.class_eval do
          extend ModeInterface
          self.major = true
        end
      end
    end

    module IsMinorMode
      def self.include(base)
        base.class_eval do
          extend ModeInterface
          self.major = false
        end
      end
    end
  end
end
