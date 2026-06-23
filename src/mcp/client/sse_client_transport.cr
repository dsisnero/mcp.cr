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
        retry_delay = 1.seconds
        last_event_id : String? = nil

        loop do
          break if @done.closed?

          begin
            @http_client.not_nil!.get(uri.request_target, headers: build_headers(last_event_id)) do |response|
              unless response.success?
                raise "SSE connection failed: HTTP #{response.status_code}"
              end

              retry_delay = 1.seconds

              MCP::Shared.parse_sse_events(response.body_io).each do |sse_event|
                if sse_event.event == "endpoint"
                  @post_endpoint = sse_event.data unless sse_event.data.empty?
                  next
                end

                last_event_id = sse_event.id if sse_event.id

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

    private def build_headers(last_event_id : String?)
      hdr = HTTP::Headers.new
      @headers.each { |k, v| hdr[k] = v }
      hdr["Last-Event-ID"] = last_event_id if last_event_id
      hdr
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
