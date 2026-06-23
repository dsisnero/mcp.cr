# Streaming SSE event parser for the MCP client transport.
#
# Parses raw `text/event-stream` (W3C SSE) from an `IO` into
# `SSEEvent` structs.  Handles multi-line `data:` concatenation,
# comment lines (`: ...`), CRLF stripping, `id` / `event` /
# `retry` fields, and space-stripping after `:` per the SSE spec.
#
# Used internally by `SseClientTransport` to parse incoming
# server-to-client SSE frames.
#
# ```
# io = IO::Memory.new("data: hello\n\n")
# events = MCP::Shared.parse_sse_events(io)
# events[0].data # => "hello"
# ```

module MCP::Shared
  # A parsed Server-Sent Events frame.
  struct SSEEvent
    property id : String?
    # Defaults to "message" per the SSE spec when no `event:` field present.
    property event : String
    property data : String
    property retry : Int32?

    def initialize(@id = nil, @event = "message", @data = "", @retry = nil)
    end
  end

  # Parse SSE events from an IO stream, returning an array of parsed frames.
  # Trailing incomplete events (no blank-line terminator) are discarded.
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
      # Per SSE spec: strip the single leading space after `:`
      value = value ? value.lstrip(' ') : ""
      event.set_field(field, value)
    end

    events
  end

  # Accumulates fields for a single SSE event as lines arrive.
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
