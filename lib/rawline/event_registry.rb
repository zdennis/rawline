module RawLine
  class EventRegistry
    def initialize(&blk)
      @subscribers = Hash.new{ |h,k| h[k.to_sym] = [] }
      blk.call(self) if block_given?
    end

    def subscribe(event_name, *subscribers, &blk)
      subscribers << blk if block_given?
      subscriptions = subscribers.map do |s|
        { subscriber: s, once: false }
      end
      @subscribers[event_name.to_sym].concat subscriptions
    end

    def subscribe_once(event_name, *subscribers, &blk)
      subscribers << blk if block_given?
      subscriptions = subscribers.map do |s|
        { subscriber: s, once: true }
      end
      @subscribers[event_name.to_sym].concat subscriptions
    end

    def subscribers_for_event(event_name)
      @subscribers[event_name.to_sym]
    end

    def unsubscribe(subscription, event_name)
      @subscribers[event_name.to_sym].delete subscription
    end
  end
end
