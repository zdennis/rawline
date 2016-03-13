module RawLine
  class NonBlockingInput
    def initialize(input)
      @input = input
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
        retry if IO.select([@input], [], [], 0.01)

        @input.fcntl(Fcntl::F_SETFL, file_descriptor_flags)
      end
      bytes
    end
  end
end
