module RawLine
  class NonBlockingInput
    DEFAULT_WAIT_TIMEOUT_IN_SECONDS = 0.01

    attr_accessor :wait_timeout_in_seconds

    def initialize(input)
      @input = input
      restore_default_timeout
    end

    def restore_default_timeout
      @wait_timeout_in_seconds = DEFAULT_WAIT_TIMEOUT_IN_SECONDS
    end

    def read
      bytes = []
      begin
        file_descriptor_flags = @input.fcntl(Fcntl::F_GETFL, 0)
        loop do
          string = @input.read_nonblock(4096)
          bytes.concat string.bytes
        end
      rescue IO::WaitReadable
        # reset flags so O_NONBLOCK is turned off on the file descriptor
        # if it was turned on during the read_nonblock above
        retry if IO.select([@input], [], [], @wait_timeout_in_seconds)

        @input.fcntl(Fcntl::F_SETFL, file_descriptor_flags)
      end
      bytes
    end
  end
end
