module RawLine
  class EventRegistry
    def initialize(&blk)
      @subscribers = Hash.new{ |h,k| h[k.to_sym] = [] }
      blk.call(self) if block_given?
    end

    def subscribe(event_name, *subscribers, &blk)
      subscribers << blk if block_given?
      @subscribers[event_name.to_sym].concat(subscribers)
    end

    def subscribers_for_event(event_name)
      @subscribers[event_name.to_sym]
    end
  end
end
