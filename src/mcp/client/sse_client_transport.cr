# MCP SSE client transport: connects to a remote MCP server over
# Server-Sent Events and HTTP POST (bidirectional).
#
# On `start`, issues an HTTP GET to the endpoint URL and parses the
# streaming `text/event-stream` response via `parse_sse_events`.
# Incoming JSON-RPC messages are dispatched through the inherited
# `on_message` callback.
#
# The transport automatically extracts the POST endpoint from an
# `event: endpoint` SSE control frame, then uses it for subsequent
# `send` calls.  If no endpoint event arrives, `send` posts to the
# original GET URL.
#
# On stream close (graceful EOF or `IO::Error`), the transport
# reconnects with exponential backoff (1s initial, 30s max) and
# sends the `Last-Event-ID` header.
#
# ```
# transport = MCP::Client::SseClientTransport.new("http://host:port/sse")
# transport.on_message { |msg| handle_message(msg) }
# transport.start
#
# transport.send(PingRequest.new)
# transport.close
# ```

require "http/client"
require "../shared"

module MCP::Client
  class SseClientTransport < MCP::Shared::AbstractTransport
    getter endpoint : String

    @http_client : HTTP::Client?
    @headers : Hash(String, String)
    # Extracted from the `event: endpoint` SSE control frame.
    @post_endpoint : String?
    # Closed by `close` to signal the reader fiber to stop.
    @done = Channel(Bool).new

    # `endpoint` is the full URL (e.g. `http://host:port/sse`).
    def initialize(@endpoint : String)
      super()
      @headers = {"Accept" => "text/event-stream", "Cache-Control" => "no-cache"}
    end

    def with_header(key : String, value : String) : self
      @headers[key] = value
      self
    end

    # Start the SSE connection.  Spawns a long-lived fiber that reads
    # the event stream and, when the stream ends, reconnects with
    # exponential backoff.
    def start
      uri = URI.parse(@endpoint)
      @http_client = HTTP::Client.new(uri)

      spawn(name: "sse-reader") do
        retry_delay = 1.seconds
        last_event_id : String? = nil

        loop do
          break if @done.closed?

          begin
            # HTTP GET with block form — gives access to body_io while the
            # connection is still open (streaming).
            @http_client.not_nil!.get(uri.request_target, headers: build_headers(last_event_id)) do |response|
              unless response.success?
                raise "SSE connection failed: HTTP #{response.status_code}"
              end

              # Reset backoff when we successfully connect.
              retry_delay = 1.seconds

              MCP::Shared.parse_sse_events(response.body_io).each do |sse_event|
                # `event: endpoint` is a control frame — capture the POST URL
                # from its data field for use by `send`.
                if sse_event.event == "endpoint"
                  @post_endpoint = sse_event.data unless sse_event.data.empty?
                  next
                end

                # Track the last event id for reconnect.
                last_event_id = sse_event.id if sse_event.id

                # Only `event: message` (or blank event) frames carry
                # JSON-RPC payloads.
                next unless sse_event.event == "message"
                next if sse_event.data.empty?

                begin
                  msg = MCP::Protocol::JSONRPCMessage.from_json(sse_event.data)
                rescue ex : JSON::ParseException
                  next
                end

                _on_message.call(msg)
              end
            end

            break if @done.closed?

            sleep retry_delay
            retry_delay = {retry_delay * 2, 30.seconds}.min
          rescue ex : IO::Error
            break if @done.closed?
            sleep retry_delay
            retry_delay = {retry_delay * 2, 30.seconds}.min
          rescue ex
            break if @done.closed?
            break unless @done.closed?
            nil
          end
        end
      rescue ex
        nil
      ensure
        _on_close.call
      end
    end

    # Build HTTP headers for a (re-)connection request, including
    # `Last-Event-ID` when the previous stream assigned an id.
    private def build_headers(last_event_id : String?)
      hdr = HTTP::Headers.new
      @headers.each { |k, v| hdr[k] = v }
      hdr["Last-Event-ID"] = last_event_id if last_event_id
      hdr
    end

    # Send a client-to-server message via HTTP POST.
    # The POST URL is either the extracted endpoint (from an `event: endpoint`
    # frame) or the original GET URL.
    def send(message : MCP::Protocol::JSONRPCMessage)
      uri = URI.parse(@endpoint)
      path = @post_endpoint || uri.request_target
      client = @http_client || HTTP::Client.new(uri)

      http_headers = HTTP::Headers.new
      http_headers["Content-Type"] = "application/json"
      @headers.each { |k, v| http_headers[k] ||= v }

      response = client.post(path, headers: http_headers, body: message.to_json)

      unless response.success?
        raise "SSE POST failed: HTTP #{response.status_code}"
      end
    rescue ex : IO::Error
      raise ex
    end

    # Close the reader fiber (signalled via `@done` channel) and the
    # underlying HTTP client.
    def close
      @done.close
      @http_client.try &.close rescue nil
    end
  end
end
