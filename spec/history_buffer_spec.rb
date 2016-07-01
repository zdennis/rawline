#!/usr/bin/env ruby

require_relative "../lib/rawline/history_buffer.rb"

describe RawLine::HistoryBuffer do
  before do
    @history = RawLine::HistoryBuffer.new(5)
  end

  it "instantiates an empty array when created" do
    expect(@history.length).to eq(0)
  end

  it "allows items to be added to the history" do
    @history.duplicates = false
    @history << "line #1"
    @history << "line #2"
    @history << "line #3"
    @history << "line #2"
    expect(@history).to eq(["line #1",  "line #2", "line #3"])
    @history.duplicates = true
    @history << "line #3"
    expect(@history).to eq(["line #1", "line #2", "line #3", "line #3"])
    @history.exclude = lambda { |i| i.match(/line #[456]/) }
    @history << "line #4"
    @history << "line #5"
    @history << "line #6"
    expect(@history).to eq(["line #1", "line #2", "line #3", "line #3"])
  end

  it "does not overflow" do
    @history << "line #1"
    @history << "line #2"
    @history << "line #3"
    @history << "line #4"
    @history << "line #5"
    @history << "line #6"
    expect(@history.length).to eq(5)
  end

  it "allows navigation back and forward" do
    @history.back
    @history.forward
    expect(@history.position).to eq(nil)
    @history << "line #1"
    @history << "line #2"
    @history << "line #3"
    @history << "line #4"
    @history << "line #5"
    @history.back
    @history.back
    @history.back
    @history.back
    @history.back
    expect(@history.position).to eq(0)
    @history.back
    expect(@history.position).to eq(0)
    @history.forward
    expect(@history.position).to eq(1)
    @history.forward
    @history.forward
    @history.forward
    @history.forward
    expect(@history.position).to eq(4)
    @history.forward
    expect(@history.position).to eq(4)
    @history.cycle = true
    @history.forward
    @history.forward
    expect(@history.position).to eq(1)
  end

  it "can retrieve the last element or the element at @position via 'get'" do
    expect(@history.get).to eq(nil)
    @history << "line #1"
    @history << "line #2"
    @history << "line #3"
    @history << "line #4"
    @history << "line #5"
    expect(@history.get).to eq("line #5")
    @history.back
    expect(@history.get).to eq("line #4")
    @history.forward
    expect(@history.get).to eq("line #5")
  end

  it "can be cleared and resized" do
    @history << "line #1"
    @history << "line #2"
    @history << "line #3"
    @history << "line #4"
    @history << "line #5"
    @history.back
    @history.back
    expect(@history.get).to eq("line #4")
    @history.resize(6)
    expect(@history.position).to eq(nil)
    @history << "line #6"
    expect(@history.get).to eq("line #6")
    @history.empty
    expect(@history).to eq([])
    expect(@history.size).to eq(6)
    expect(@history.position).to eq(nil)
  end

  describe 'finding matches in history, forward and backward' do
    before do
      @history.resize(100)
      @history << 'echo foo'
      @history << 'echo bar'
      @history << 'echo baz'
      @history << 'echo food'
      @history << 'echo bark'
      @history << 'echo bonanza'
    end

    describe '#find_match_backward' do
      context 'when the position starts as nil' do
        it 'finds the first item back that matches' do
          @history.clear_position
          expect(@history.find_match_backward('bonanza')).to eq 'echo bonanza'

          @history.clear_position
          expect(@history.find_match_backward('foo')).to eq 'echo food'
        end

        it 'can find consecutive matches, skipping unmatched items' do
          @history.clear_position
          expect(@history.find_match_backward('foo')).to eq 'echo food'
          $z = true
          expect(@history.find_match_backward('foo')).to eq 'echo foo'
        end
      end

      context 'when the position starts as non-nil' do
        it 'finds the first item back that matches from the current position' do
          3.times { @history.back }
          expect(@history.find_match_backward('bar')).to eq 'echo bar'
        end
      end
    end

    describe '#find_match_forward' do
      context 'when the position starts as nil' do
        it 'finds the first item from the beginning that matches' do
          @history.clear_position
          expect(@history.find_match_forward('bar')).to eq 'echo bar'
          expect(@history.position).to eq @history.index('echo bar')

          @history.clear_position
          expect(@history.find_match_forward('foo')).to eq 'echo foo'
          expect(@history.position).to eq @history.index('echo foo')
        end

        it 'can find consecutive matches, skipping unmatched items' do
          @history.clear_position
          expect(@history.find_match_forward('foo')).to eq 'echo foo'
          expect(@history.position).to eq @history.index('echo foo')

          expect(@history.find_match_forward('foo')).to eq 'echo food'
          expect(@history.position).to eq @history.index('echo food')
        end
      end

      context 'when the position starts as non-nil' do
        it 'finds the first item back that matches from the current position' do
          3.times { @history.back }
          expect(@history.find_match_forward('bar')).to eq 'echo bark'
          expect(@history.position).to eq @history.index('echo bark')
        end
      end

      context 'when its gone all the way back, and we want to go forward' do
        it 'd' do
          @history.length.times do
            @history.find_match_backward('bar')
          end
          expect(@history.find_match_forward('bar')).to eq 'echo bark'
        end
      end
    end

  end
end
