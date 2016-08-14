#!/usr/bin/env ruby

require 'highline/system_extensions'

module HighLine::SystemExtensions
  # Override Windows' character reading so it's not tied to STDIN.
  def get_character( input = STDIN )
    (RUBY_VERSION.gsub(/1\./, '').to_f >= 8.7) ? input.getbyte : input.getc
  end
end

require 'stringio'
require_relative "../lib/rawline.rb"

class DummyInput < RawLine::NonBlockingInput
  def initialize
    @input = StringIO.new
  end

  def read
    @input.read.bytes
  end

  def clear
    @input = StringIO.new
  end

  def <<(bytes)
    @input << bytes
  end

  def rewind
    @input.rewind
  end
end

class DummyKeyboardInputProcessor
  attr_reader :bytes_read

  def initialize
    @bytes_read = []
  end

  def read_bytes(bytes)
    @bytes_read.push *bytes
    []
  end
end

describe RawLine::Editor do
  let(:dom) { RawLine::DomTree.new }
  let(:renderer) do
    instance_double(RawLine::Renderer,
      pause: nil,
      unpause: nil,
      render_cursor: nil,
      render: nil
    )
  end
  let(:input) { DummyInput.new }
  let(:terminal) do
    output = double("IO", cooked: nil)
    RawLine::VT220Terminal.new(input, output)
  end

  before do
    @editor = RawLine::Editor.new(
      dom: dom,
      input: input,
      renderer: renderer,
      terminal: terminal
    ) do |editor|
      editor.prompt = ">"
    end
    @editor.event_loop.tick
    @editor.on_read_line do |event|
      line = event[:payload][:line]
    end
  end

  it "reads raw characters from @input" do
    input << "test #1"
    input.rewind
    @editor.event_loop.tick
    expect(@editor.line.text).to eq("test #1")
    expect(@editor.dom.input_box.content).to eq("test #1")
  end

  describe 'binding keys to code blocks' do
    it 'raises a BindingException when trying with bind with an unrecognized escape code' do
      @editor.terminal.escape_codes = [] # remove any existing escape codes
      expect do
        @editor.bind(test: "\etest") { "test #2e" }
      end.to raise_error(RawLine::BindingException)
    end

    it 'does not raise an error when using a recognized escape code' do
      @editor.terminal.escape_codes << ?\e.ord

      expect do
        @editor.bind(test: "\etest") { }
      end.to_not raise_error

      expect do
        @editor.bind("\etest2") { }
      end.to_not raise_error
    end

    it 'binds Ctrl sequences to code blocks with bytes' do
      @editor.bind(?\C-w) { @editor.write "test #2a" }
      input << ?\C-w
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.text).to eq("test #2a")
    end

    it 'binds Ctrl sequences to code blocks with :ctrl_<letter>' do
      @editor.bind(:ctrl_w) { @editor.write "test #2a" }
      input << ?\C-w
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.text).to eq("test #2a")
    end

    it 'binds with a single byte representing the key-code' do
      @editor.bind(21) { @editor.write "test #2c" }
      input << ?\C-u
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.text).to eq("test #2c")
    end

    it 'binds with a single byte array representing the key code' do
      @editor.bind([22]) { @editor.write "test #2d" }
      input << ?\C-v
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.text).to eq("test #2d")
    end

    it 'binds with a multi byte array representing the key code' do
      @editor.bind(test: "\etest") { @editor.write "test #2e" }
      input << ?\e << ?t << ?e << ?s << ?t
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.text).to eq("test #2e")
    end
  end

  describe 'bubbling key bindings up the environment stack' do
    let(:input_processor) { DummyKeyboardInputProcessor.new }

    before do
      @editor.bind(?\C-e) { @editor.write "echo hi" }
    end

    it 'does not bubble up key bindings by default' do
      @editor.push_new_env do |env|
        env.push_keyboard_input_processor input_processor
      end

      input << ?\C-e
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.text).to_not match "echo hi"
    end

    it 'bubbles up key bindings when told to do so' do
      @editor.push_new_env do |env|
        env.key_bindings_fall_back_to_parent = true
      end

      input << ?\C-e
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.text).to eq "echo hi"
    end

    it 'bubbles up multiple environments' do
      3.times do
        @editor.push_new_env(key_bindings_fall_back_to_parent: true)
      end

      input << ?\C-e
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.text).to eq "echo hi"
    end

    it 'stops at the first binding found' do
      custom_envs = []
      3.times do
        custom_envs << @editor.push_new_env(key_bindings_fall_back_to_parent: true)
      end
      custom_envs[1].bind(?\C-e) { @editor.write "what up doc?" }

      input << ?\C-e
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.text).to eq "what up doc?"
      expect(@editor.line.text).to_not match "echo hi"
    end
  end

  it "keeps track of the cursor position" do
    input << "test #4"
    input.rewind
    @editor.event_loop.tick
    expect(@editor.line.position).to eq(7)
    3.times { @editor.move_left }
    expect(@editor.line.position).to eq(4)
    2.times { @editor.move_right }
    expect(@editor.line.position).to eq(6)
  end

  describe "keeping track of the cursor position across terminal lines (e.g. multi-line editing)" do
    let(:terminal_width){ 3 }
    let(:terminal_height){ 7 }
    let(:arrow_key_left_ansi){ "\e[D" }
    let(:arrow_key_right_ansi){ "\e[C" }

    before do
      allow(@editor.terminal).to receive(:terminal_size).and_return [terminal_width, terminal_height]
    end

    context "and the cursor position is at the first character of the second line" do
      before do
        input << "123"
        input.rewind
      end

      it "is at the first character of a second line" do
        @editor.event_loop.tick
        expect(@editor.line.position).to eq(3)
      end

      describe "moving left from the first position of the second line" do
        it "moves the line and cursor position to left by 1 character" do
          @editor.event_loop.tick
          expect(@editor.line.position).to eq(3)
          expect(@editor.input_box.position).to eq(3)

          input.clear
          input << arrow_key_left_ansi
          input.rewind

          @editor.event_loop.reset
          @editor.event_loop.tick

          expect(@editor.line.position).to eq(2)
          expect(@editor.input_box.position).to eq(2)
        end
      end

      describe "moving right from the first position of the second line" do
        it "doesnt move the line and cursor position" do
          @editor.event_loop.tick
          expect(@editor.line.position).to eq(3)
          expect(@editor.input_box.position).to eq(3)

          input.clear
          input << arrow_key_right_ansi
          input.rewind

          @editor.event_loop.reset
          @editor.event_loop.tick

          expect(@editor.line.position).to eq(3)
          expect(@editor.input_box.position).to eq(3)
        end
      end

      describe "moving left to the previous line then right to the next line" do
        before do
          @editor.event_loop.tick

          # this is the one that moves us to the previous line
          input.clear
          input << arrow_key_left_ansi
          input.rewind
          @editor.event_loop.reset
          @editor.event_loop.tick

          # these are for fun to show that we don't generate unnecessary
          # escape sequences
          input.clear
          input << arrow_key_left_ansi
          input << arrow_key_left_ansi
          input << arrow_key_left_ansi
          input.rewind
          @editor.event_loop.reset
          @editor.event_loop.tick

          # now let's move right again
          input.clear
          input << arrow_key_right_ansi
          input << arrow_key_right_ansi
          input << arrow_key_right_ansi
          input.rewind
          @editor.event_loop.reset
          @editor.event_loop.tick

          # this is the one that puts us on the next line
          input.clear
          input << arrow_key_right_ansi
          input.rewind
          @editor.event_loop.reset
          @editor.event_loop.tick
        end

        it "correctly sets the line and cursor position" do
          expect(@editor.line.position).to eq(3)
          expect(@editor.input_box.position).to eq(3)
        end
      end
    end
  end

  describe "#insert" do
    before do
      input << "test #5"
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.position).to eq(7)
    end

    it "inserts the given string at the current line position" do
      @editor.insert "ABC"
      expect(@editor.line.text).to eq("test #5ABC")
    end

    it "increments the line position the length of the inserted string" do
      @editor.insert "ABC"
      expect(@editor.line.position).to eq(10)
    end

    it "shifts characters not at the end of the string" do
      @editor.move_left
      @editor.insert "931"
      expect(@editor.line.text).to eq("test #9315")
      expect(@editor.line.position).to eq(9)
    end

    it "updates the DOM's input_box and position" do
      @editor.insert "hello"
      expect(dom.input_box.content).to eq("test #5hello")
      expect(dom.input_box.position).to eq(12)
    end
  end

  describe "#write" do
    before do
      input << "test #5"
      input.rewind
      @editor.event_loop.tick
      expect(@editor.line.position).to eq(7)
    end

    it "writes the given string at the current line position" do
      @editor.write "ABC"
      expect(@editor.line.text).to eq("test #5ABC")
    end

    it "increments the line position the length of the written string" do
      @editor.write "ABC"
      expect(@editor.line.position).to eq(10)
    end

    it "overwrites any character at the current position" do
      @editor.move_left
      @editor.write "931"
      expect(@editor.line.text).to eq("test #931")
      expect(@editor.line.position).to eq(9)
    end

    it "updates the DOM's input_box and position" do
      @editor.move_left
      @editor.write "hello"
      expect(dom.input_box.content).to eq("test #hello")
      expect(dom.input_box.position).to eq(11)
    end
  end

  it "can delete characters" do
    input << "test #5"
    input.rewind
    @editor.event_loop.tick
    3.times { @editor.move_left }
    4.times { @editor.delete_left_character }
    3.times { @editor.delete_character }
    expect(@editor.line.text).to eq("")
    expect(@editor.line.position).to eq(0)
  end

  it "can clear the whole line" do
    input << "test #5"
    input.rewind
    @editor.event_loop.tick
    @editor.clear_line
    expect(@editor.line.text).to eq("")
    expect(@editor.line.position).to eq(0)
  end

  it "supports undo and redo" do
    input << "test #6"
    input.rewind
    @editor.event_loop.tick
    3.times { @editor.delete_left_character }
    2.times { @editor.undo }
    expect(@editor.line.text).to eq("test #")
    2.times { @editor.redo }
    expect(@editor.line.text).to eq("test")
  end

  xit "supports history" do
    input << "test #7a"
    input.rewind
    @editor.read "", true
    @editor.newline
    @input << "test #7b"
    @input.pos = 8
    @editor.read "", true
    @editor.newline
    @input << "test #7c"
    @input.pos = 16
    @editor.read "", true
    @editor.newline
    @input << "test #7d"
    @input.pos = 24
    @editor.read "", true
    @editor.newline
    @editor.history_back
    expect(@editor.line.text).to eq("test #7c")
    10.times { @editor.history_back }
    expect(@editor.line.text).to eq("test #7a")
    2.times { @editor.history_forward }
    expect(@editor.line.text).to eq("test #7c")
  end

  it "can overwrite lines" do
    input << "test #8a"
    input.rewind
    @editor.event_loop.tick
    @editor.overwrite_line("test #8b", position: 2)
    expect(@editor.line.text).to eq("test #8b")
    expect(@editor.line.position).to eq(2)
  end

  xit "can complete words" do
    @editor.completion_append_string = "\t"
    @editor.bind(:tab) { @editor.complete }
    @editor.completion_proc = lambda do |word|
      if word then
         ['select', 'update', 'delete', 'debug', 'destroy'].find_all  { |e| e.match(/^#{Regexp.escape(word)}/) }
      end
    end
    input << "test #9 de" << ?\t.chr << ?\t.chr
    input.rewind
    @editor.event_loop.tick
    expect(@editor.line.text).to eq("test #9 delete\t")
  end

  xit "supports INSERT and REPLACE modes" do
    input << "test 0"
    @editor.terminal.keys[:left_arrow].each { |k| input << k.chr }
    input << "#1"
    input.rewind
    @editor.event_loop.tick
    expect(@editor.line.text).to eq("test #10")
    @editor.toggle_mode
    input << "test 0"
    @editor.terminal.keys[:left_arrow].each { |k| input << k.chr }
    input << "#1"
    input.rewind
    @editor.event_loop.tick
    expect(@editor.line.text).to eq("test #1test #1")
  end

  describe '#puts' do
    it 'puts to the terminal, then re-renders' do
      expect(terminal).to receive(:puts).with("A", "B", "C").ordered
      expect(renderer).to receive(:render).with(reset: true)
      @editor.puts("A", "B", "C")
    end
  end
end
