require "http/client"
require "../shared"

module MCP::Client
  class SseClientTransport < MCP::Shared::AbstractTransport
    getter endpoint : String

    @http_client : HTTP::Client?
    @headers : Hash(String, String)
    @post_endpoint : String?
    @done = Channel(Bool).new

    def initialize(@endpoint : String)
      super()
      @headers = {"Accept" => "text/event-stream", "Cache-Control" => "no-cache"}
    end

    def with_header(key : String, value : String) : self
      @headers[key] = value
      self
    end

    def start
      uri = URI.parse(@endpoint)
      @http_client = HTTP::Client.new(uri)

      spawn(name: "sse-reader") do
        begin
          @http_client.not_nil!.get(uri.request_target, headers: HTTP::Headers.new.tap { |hdr|
            @headers.each { |k, v| hdr[k] = v }
          }) do |response|
            unless response.success?
              raise "SSE connection failed: HTTP #{response.status_code}"
            end

            MCP::Shared.parse_sse_events(response.body_io).each do |sse_event|
              if sse_event.event == "endpoint"
                @post_endpoint = sse_event.data unless sse_event.data.empty?
                next
              end
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
        rescue ex : IO::Error
          nil
        rescue ex
          nil
        ensure
          _on_close.call unless @done.closed?
        end
      end
    end

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

    def close
      @done.close
      @http_client.try &.close rescue nil
    end
  end
end
