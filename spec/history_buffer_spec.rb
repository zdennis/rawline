#!/usr/bin/env ruby

require_relative "../lib/rawline/history_buffer.rb"

describe RawLine::HistoryBuffer do
  subject(:history) do
    RawLine::HistoryBuffer.new(100)
  end
  let(:empty_history) { RawLine::HistoryBuffer.new(0) }

  def build_history(*items)
    described_class.new(items.length).tap do |history|
      items.each { |item| history << item }
    end
  end

  describe '.new_with_infinite_size' do
    let(:infinity) { 1.0 / 0.0 }
    it 'returns a new HistoryBuffer of an infinite size' do
      history = described_class.new_with_infinite_size
      expect(history).to be_kind_of(described_class)
      expect(history.size).to eq(infinity)
    end
  end

  describe '#[]' do
    before { history << 'foo' << 'bar' }

    it 'returns the history item at the given index' do
      expect(history[0]).to eq 'foo'
      expect(history[1]).to eq 'bar'
    end

    it 'returns nil when there is no item at the index' do
      expect(history[2]).to be(nil)
    end
  end

  describe '#any?' do
    it 'returns true when there is at least one item in the history' do
      history << 'item 1'
      expect(history.any?).to be(true)
    end

    it 'returns false otherwise' do
      expect(history.any?).to be(false)
    end

    context 'called with a block' do
      before { history << 'item 1' << 'item 2' }

      it 'returns true the block returns true for any item in the history' do
        expect(history.any?{ |item| item =~ /1/ }).to be(true)
      end

      it 'returns false otherwise' do
        expect(history.any?{ |item| item =~ /z/ }).to be(false)
      end
    end
  end

  describe '#beginning?' do
    before do
      history << 'item 1' << 'item 2'
    end

    it 'returns false when the position is nil' do
      history.position = nil
      expect(history.beginning?).to be(false)
    end

    it 'returns true when the position is at the beginning' do
      history.position = 0
      expect(history.beginning?).to be(true)
    end

    it 'returns false otherwise' do
      history.position = 1
      expect(history.beginning?).to be(false)
    end
  end

  describe '#clear' do
    before { history << 'item 1' << 'item 2' }

    it 'forgets all history items' do
      history.clear
      expect(history).to eq empty_history
    end

    it 'clears the position' do
      history.forward
      expect do
        history.clear
      end.to change { history.position }.to nil
    end
  end

  describe '#clear_position' do
    before do
      history << 'item 1' << 'item 2'
      history.position = 1
    end

    it 'clears the position' do
      expect do
        history.clear_position
      end.to change { history.position }.to nil
    end
  end

  describe '#detect' do
    before { history << 'item 1' << 'item 2' << 'item 22' }
    it 'returns the first item that matches the given block' do
      expect(history.detect { |item| item =~ /2/ }).to eq('item 2')
    end

    it 'returns nil when there is no matching item' do
      expect(history.detect { |item| item =~ /z/ }).to be(nil)
    end
  end

  describe '#duplicates' do
    it 'allows duplicates by default' do
      expect(history.duplicates).to be(true)
    end
  end

  describe '#each' do
    before { history << 'foo' << 'bar' << 'baz' }

    it 'iterates over each item in the history, oldest to newest' do
      results = []
      history.each do |item|
        results << item
      end
      expect(results).to eq ['foo', 'bar', 'baz']
    end
  end

  describe '#empty?' do
    it 'returns true when there are not history items' do
      expect(empty_history.empty?).to be(true)
    end

    it 'returns false when there are history items' do
      history << 'item 1'
      expect(history.empty?).to be(false)
    end
  end

  describe '#end?' do
    before do
      history << 'item 1' << 'item 2'
    end

    it 'returns false when the position is nil' do
      history.position = nil
      expect(history.end?).to be(false)
    end

    it 'returns true when the position is at the end' do
      history.position = 1
      expect(history.end?).to be(true)
    end

    it 'returns false otherwise' do
      history.position = 0
      expect(history.end?).to be(false)
    end
  end

  describe '#first' do
    it 'returns the first history item' do
      history << 'item 1' << 'item 2'
      expect(history.first).to eq 'item 1'
    end

    it 'returns nil when there are no history items' do
      expect(history.first).to be(nil)
    end
  end

  describe '#first!' do
    before do
      history << 'item 1' << 'item 2' << 'item 3'
      history.forward
      history.forward
      expect(history.beginning?).to be(false)
    end

    it 'sets the position to the beginning of the HistoryBuffer' do
      history.first!
      expect(history.beginning?).to be(true)
      expect(history.position).to eq(0)
    end

    it 'returns the first history item' do
      expect(history.first!).to eq('item 1')
    end
  end

  describe '#get' do
    before do
      history << 'item 1'
      history << 'item 2'
      history << 'item 3'
    end

    context 'and there is no position' do
      before { expect(history.position).to be(nil) }

      it 'returns the last item' do
        expect(history.get).to eq('item 3')
      end

      it 'sets the position to that of the last item' do
        expect do
          history.get
        end.to change { history.position }.to history.length - 1
      end
    end

    context 'and there is a position' do
      before { history.back }

      it 'returns the item at the current position' do
        expect(history.get).to eq('item 3')
      end
    end
  end

  describe '#length' do
    it 'is empty when newly created' do
      expect(history.empty?).to be(true)
      expect(history.length).to eq(0)
    end
  end

  describe '#<<' do
    it 'appends the given item to the history' do
      history << "line #1"
      history << "line #2"
      history << "line #2"
      history << "line #3"
      expect(history).to eq(build_history('line #1', 'line #2', 'line #2', 'line #3'))
    end

    context 'and duplicates are disabled' do
      before do
        history.duplicates = false
      end

      it 'does not append a duplicate item' do
        history << "line #1"
        history << "line #1"
        history << "line #1"
        expect(history).to eq(build_history('line #1'))
      end

      it 'allows duplicate item that are not next to each other in the history' do
        history << "line #1"
        history << "line #2"
        history << "line #1"
        expect(history).to eq(build_history('line #1', 'line #2', 'line #1'))
      end
    end

    context 'and there is an exclusion filter' do
      before do
        history.exclude = -> (i) { i.match(/line #[13]/) }
      end

      it 'does not append excluded items' do
        history << "line #1"
        history << "line #2"
        history << "line #3"
        history << "line #4"
        expect(history).to eq(build_history('line #2', 'line #4'))
      end
    end

    context 'and the history has a set size' do
      subject(:history) { described_class.new(size) }
      let(:size) { 2 }

      it 'does not overflow' do
        3.times { history << 'apples' }
        expect(history).to eq(build_history('apples', 'apples'))
      end
    end
  end

  describe 'finding matches in history, forward and backward' do
    before do
      history.resize(100)
      history << 'echo foo'
      history << 'echo bar'
      history << 'echo baz'
      history << 'echo food'
      history << 'echo bark'
      history << 'echo bonanza'
    end

    describe '#find_match_backward' do
      it 'finds the first item back whose start matches' do
        expect(history.find_match_backward('echo b')).to eq 'echo bonanza'
      end

      it 'does not find partial matches' do
        expect(history.find_match_backward('bonanza')).to be nil
      end

      context 'when the position starts as nil' do
        it 'finds the first item back whose start matches' do
          history.clear_position
          expect(history.find_match_backward('echo b')).to eq 'echo bonanza'

          history.clear_position
          expect(history.find_match_backward('echo f')).to eq 'echo food'
        end

        it 'can find consecutive matches, skipping unmatched items' do
          history.clear_position
          expect(history.find_match_backward('echo f')).to eq 'echo food'
          expect(history.find_match_backward('echo f')).to eq 'echo foo'
        end
      end

      context 'when the position starts as non-nil' do
        it 'finds the first item back that matches from the current position' do
          3.times { history.back }
          expect(history.find_match_backward('echo b')).to eq 'echo baz'
        end
      end

      context 'when the HistoryBuffer is not cyclic' do
        before { history.cycle = false }

        it 'stops searching at the very first item in the HistoryBuffer' do
          history.find_match_backward('echo foo')
          expect(history.get).to eq('echo food')

          history.find_match_backward('echo foo')
          expect(history.get).to eq('echo foo')
          expect(history.beginning?).to be(true)

          history.find_match_backward('echo foo')
          expect(history.get).to eq('echo foo')
          expect(history.beginning?).to be(true)
        end
      end

      context 'when the HistoryBuffer is cyclic' do
        before { history.cycle = true }

        it 'wraps aorund and searches from the end of hte HistoryBuffer' do
          history.find_match_backward('echo foo')
          expect(history.get).to eq('echo food')

          history.find_match_backward('echo foo')
          expect(history.get).to eq('echo foo')
          expect(history.beginning?).to be(true)

          history.find_match_backward('echo foo')
          expect(history.get).to eq('echo food')
          expect(history.beginning?).to be(false)
        end
      end
    end

    describe '#find_match_forward' do
      it 'finds the first item forward whose start matches' do
        expect(history.find_match_forward('echo b')).to eq 'echo bar'
      end

      it 'does not find partial matches' do
        expect(history.find_match_forward('bonanza')).to be nil
      end

      context 'when the position starts as nil' do
        it 'finds the first item from the beginning that matches' do
          history.clear_position
          expect(history.find_match_forward('echo b')).to eq 'echo bar'
          expect(history.position).to eq history.index('echo bar')

          history.clear_position
          expect(history.find_match_forward('echo f')).to eq 'echo foo'
          expect(history.position).to eq history.index('echo foo')
        end

        it 'can find consecutive matches, skipping unmatched items' do
          history.clear_position
          expect(history.find_match_forward('echo f')).to eq 'echo foo'
          expect(history.position).to eq history.index('echo foo')

          expect(history.find_match_forward('echo f')).to eq 'echo food'
          expect(history.position).to eq history.index('echo food')
        end
      end

      context 'when the position starts as non-nil' do
        it 'finds the first item back that matches from the current position' do
          3.times { history.back }
          expect(history.find_match_forward('echo b')).to eq 'echo bark'
          expect(history.position).to eq history.index('echo bark')
        end
      end

      context 'when its gone all the way back, and we want to go forward' do
        it 'finds the first item forward that matches from the current position' do
          history.length.times do
            history.find_match_backward('echo bar')
          end
          expect(history.find_match_forward('echo bar')).to eq 'echo bark'
        end
      end

      context 'when the HistoryBuffer is not cyclic' do
        before do
          history.cycle = false
          history.position = 0
        end

        it 'stops searching at the very last item matched in the HistoryBuffer' do
          history.find_match_forward('echo b')
          history.find_match_forward('echo b')
          history.find_match_forward('echo b')
          expect(history.get).to eq('echo bark')

          history.find_match_forward('echo b')
          expect(history.get).to eq('echo bonanza')
          expect(history.end?).to be(true)

          history.find_match_forward('echo b')
          expect(history.end?).to be(true)
        end
      end

      context 'when the HistoryBuffer is cyclic' do
        before { history.cycle = true }

        it 'wraps aorund and searches from the end of hte HistoryBuffer' do
          history.find_match_forward('echo b')
          history.find_match_forward('echo b')
          history.find_match_forward('echo b')
          expect(history.get).to eq('echo bark')
          history.find_match_forward('echo b')
          expect(history.get).to eq('echo bonanza')
          expect(history.end?).to be(true)

          history.find_match_forward('echo bar')
          expect(history.end?).to be(false)
        end
      end

    end
  end

  describe 'navigating the history' do
    before do
      history << 'item 1'
      history << 'item 2'
      history << 'item 3'
      history << 'item 4'
      history << 'item 5'

      expect(history.position).to be(nil)
    end

    describe '#back' do
      it 'allows you to move back thru the history' do
        history.back
        expect(history.position).to be(4)
        history.back
        history.back
        expect(history.position).to be(2)
      end

      it 'does not allow you to go past the very first item' do
        100.times { history.back }
        expect(history.position).to be(0)
      end

      context 'and the history is set to cycle' do
        before { history.cycle = true }

        it 'wraps around to the very last item when you move beyond the first item' do
          history.position = 0
          expect do
            history.back
          end.to change { history.end? }.to true
        end
      end
    end

    describe '#forward' do
      context 'and you are starting with no position' do
        before { expect(history.position).to be(nil) }

        it 'puts you at the position of the last item' do
          expect do
            history.back
          end.to change { history.end? }.to true
        end
      end

      context 'and you are starting from a known position' do
        before do
          history.length.times { history.back }
          expect(history.position).to be(0)
        end

        it 'allows you to move forward thru the history' do
          history.forward
          expect(history.position).to be(1)
          history.forward
          history.forward
          expect(history.position).to be(3)
        end
      end

      it 'does not allow you to go past the very last item (by default)' do
        100.times { history.forward }
        expect do
          history.forward
        end.to_not change { history.end? }.from true
      end

      context 'and the history is set to cycle' do
        before { history.cycle = true }

        it 'wraps around to the very first item when you move beyond the last item' do
          history.position = history.length - 2
          history.forward
          expect do
            history.forward
          end.to change { history.beginning? }.to true
        end
      end
    end
  end

  describe '#map' do
    before { history << 'foo' << 'bar' << 'baz' }

    it 'iterates over each item in the history, oldest to newest' do
      results = history.map do |item|
        "echo #{item}"
      end
      expect(results).to eq ['echo foo', 'echo bar', 'echo baz']
    end
  end

  describe '#replace' do
    before { history << 'item 1' << 'item 2' }

    it 'replaces the current history items with an array of history items' do
      history.replace(['foo', 'bar'])
      expect(history).to eq build_history('foo', 'bar')
    end

    it 'replaces the current history items with a given HistoryBuffer' do
      new_history = build_history('foo', 'bar')
      history.replace(new_history)
      expect(history).to eq new_history
    end
  end

  describe '#resize' do
    before do
      history << 'item 1' << 'item 2' << 'item 3' << 'item 4'
    end

    it 'resizes the history' do
      expect do
        history.resize(2)
      end.to change { history.size }.to 2
    end

    it 'forgets any history items older than the new size allows' do
      history.resize(2)
      expect(history).to eq build_history('item 3', 'item 4')
    end
  end

  describe '#reverse' do
    before { history << 'item 1' << 'item 2' }

    it 'returns a new HistoryBuffer in reverse order' do
      reversed_history = history.reverse
      expect(reversed_history).to eq build_history('item 2', 'item 1');
    end

    it 'does not modify the original HistoryBuffer' do
      reversed_history = history.reverse
      expect(history).to eq build_history('item 1', 'item 2')
    end
  end

  describe '#size' do
    it 'returns the size of the HistoryBuffer (regardless of history items)' do
      expect(described_class.new(4).size).to eq(4)
      expect(described_class.new(128).size).to eq(128)
    end

    it 'defaults to 1024 when provided as 0 or nil' do
      expect(described_class.new(0).size).to eq(1024)
      expect(described_class.new(nil).size).to eq(1024)
    end

    it 'defaults to 1024 when not provided' do
      expect(described_class.new.size).to eq(1024)
    end
  end

  describe '#to_a' do
    it 'returns the history as an array' do
      history << 'item 1' << 'item 2'
      expect(history.to_a).to eq ['item 1', 'item 2']
    end
  end

end
