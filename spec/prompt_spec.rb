describe RawLine::Prompt do
  describe "#length" do
    it "returns the length of prompt ignoring  ANSI escape sequences" do
      prompt = RawLine::Prompt.new("\e[01;31mhello\e[00m")
      expect(prompt.length).to eq("hello".length)
    end
  end
end
