module RawLine
  class EventLoop
    attr_reader :events

    def initialize(registry:)
      @registry = registry
      @events = []
    end

    # event looks like:
    #  * name
    #  * source
    #  * target
    #  * payload
    def add_event(**event)
      next_event = @events[0]
      if next_event != event
        @events << event
      end
    end

    def recur(event:nil, interval_in_ms:, &blk)
      if block_given?
        # TODO: implement
      elsif event
        add_event event.merge(recur: { interval_in_ms: interval_in_ms, recur_at: recur_at(interval_in_ms) })
      else
        raise "Must pass in a block or an event."
      end
    end

    def start
      loop do
        event = @events.shift
        if event
          recur = event[:recur]
          if recur
            if current_time_in_ms >= recur[:recur_at]
              dispatch_event(event)
              interval_in_ms = recur[:interval_in_ms]
              add_event event.merge(recur: { interval_in_ms: interval_in_ms, recur_at: recur_at(interval_in_ms) } )
            else
              # put it back on the queue
              add_event event
              dispatch_event(default_event)
            end
          else
            dispatch_event(event)
          end
        else
          dispatch_event(default_event)
        end
      end
    end

    private

    def current_time_in_ms
      (Time.now.to_f * 1_000).to_i
    end

    def default_event
      { name: 'default', source: self }
    end

    def recur_at(interval_in_ms)
      current_time_in_ms + interval_in_ms
    end

    def dispatch_event(event)
      @registry.subscribers_for_event(event[:name]).each do |subscriber|
        subscriber.call(event)
      end
    end
  end
end
