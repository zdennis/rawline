module RawLine
  class EventLoop
    attr_reader :events

    def initialize(registry:)
      @registry = registry
      @events = []
      @counter = 0
    end

    # event looks like:
    #  * name
    #  * target
    #  * payload
    def add_event(**event, &blk)
      unless event.has_key?(:_event_callback)
        event[:_event_callback] = blk if blk
      end

      unless event.has_key?(:_event_id)
        @counter += 1
        event[:_event_id] = @counter
      end

      # if the last event is the same as the incoming then do there is no
      # need to add it again. For example, rendering events that already
      # back can be squashed into a single event.
      if @events.last != event
        @events << event
        event[:_event_id]
      else
        @events.last[:_event_id]
      end
    end

    def clear(event_id)
      @events = @events.reject { |event| event[:_event_id] == event_id }
    end

    def immediately(**event_kwargs, &blk)
      dispatch_event(event_kwargs.merge(_event_callback: blk))
    end

    def reset
      @events.clear
      @counter = 0
    end

    def once(interval_in_ms:, **event, &blk)
      add_event event.merge(once: { run_at: recur_at(interval_in_ms) }), &blk
    end

    def recur(interval_in_ms:, **event, &blk)
      add_event event.merge(recur: { interval_in_ms: interval_in_ms, recur_at: recur_at(interval_in_ms) }), &blk
    end

    def tick
      event = @events.shift
      if event
        recur = event[:recur]
        once = event[:once]
        if recur
          if current_time_in_ms >= recur[:recur_at]
            dispatch_event(event)
            interval_in_ms = recur[:interval_in_ms]
            add_event event.merge(recur: { interval_in_ms: interval_in_ms, recur_at: recur_at(interval_in_ms) } )
          else
            # put it back on the queue
            @events << event
            dispatch_event(default_event)
          end
        elsif once
          if current_time_in_ms >= once[:run_at]
            dispatch_event(event)
          else
            # put it back on the queue
            @events << event
            # add_event event
            dispatch_event(default_event)
          end
        else
          dispatch_event(event)
        end
      else
        dispatch_event(default_event)
      end
    end

    def start
      loop do
        tick
      end
    end

    private

    def current_time_in_ms
      (Time.now.to_f * 1_000).to_i
    end

    def default_event
      { name: 'default', _event_id: -1 }
    end

    def recur_at(interval_in_ms)
      current_time_in_ms + interval_in_ms
    end

    def dispatch_event(event)
      @registry.subscribers_for_event(event[:name]).each do |subscriber|
        subscriber.call(event)
      end

      callback = event[:_event_callback]
      callback.call(event) if callback
    end
  end
end
