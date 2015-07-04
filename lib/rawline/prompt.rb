require 'delegate'

module RawLine

  class Prompt < SimpleDelegator
    # Length returns the length of the prompt minus any ANSI escape sequences.
    def length
      self.gsub(/\033\[[0-9;]*m/, "").length
    end
  end

end
