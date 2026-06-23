module MCP::Shared
  struct SSEEvent
    property id : String?
    property event : String
    property data : String
    property retry : Int32?

    def initialize(@id = nil, @event = "message", @data = "", @retry = nil)
    end
  end

  def self.parse_sse_events(io : IO) : Array(SSEEvent)
    events = [] of SSEEvent
    event = PendingEvent.new

    io.each_line do |raw_line|
      line = raw_line.rstrip("\r")

      if line.empty?
        events << event.flush if event.has_any_field?
        event = PendingEvent.new
        next
      end

      next if line.starts_with?(':')

      colon_idx = line.index(':')
      next unless colon_idx

      field = line[0...colon_idx]
      value = line[(colon_idx + 1)..]?
      value = value ? value.lstrip(' ') : ""
      event.set_field(field, value)
    end

    events
  end

  private struct PendingEvent
    property id : String?
    property event : String?
    property retry : Int32?
    @data_parts = [] of String
    @has_any_field = false

    def has_any_field? : Bool
      @has_any_field
    end

    def set_field(field : String, value : String)
      @has_any_field = true
      case field
      when "id"    then @id = value.empty? ? nil : value
      when "event" then @event = value.empty? ? nil : value
      when "data"  then @data_parts << value
      when "retry" then @retry = value.to_i?
      end
    end

    def flush : SSEEvent
      SSEEvent.new(
        id: @id,
        event: @event || "message",
        data: @data_parts.join('\n'),
        retry: @retry
      )
    end
  end
end
