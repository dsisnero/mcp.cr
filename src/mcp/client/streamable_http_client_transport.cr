# MCP Streamable HTTP client transport: connects to a remote MCP server
# over a single streamable HTTP endpoint.
#
# On `send`, POSTs JSON-RPC messages to the endpoint URL with the
# `Accept: application/json, text/event-stream` and
# `Mcp-Session-Id` headers as required by the MCP Streamable HTTP spec.
# Inbound JSON-RPC messages (responses and server-initiated
# notifications) are dispatched through the inherited `on_message`
# callback.
#
# Session management: a `Mcp-Session-Id` header returned by the
# server on the initialize response is captured and replayed on all
# subsequent requests. If no session ID is returned, the transport
# operates in stateless mode.
#
# ```
# transport = MCP::Client::StreamableHttpClientTransport.from_uri("http://host:port/mcp")
# transport.on_message { |msg| handle_message(msg) }
# transport.start
#
# transport.send(PingRequest.new)
# transport.close
# ```

require "http/client"
require "../shared"

module MCP::Client
  class StreamableHttpClientTransport < MCP::Shared::AbstractTransport
    MCP_SESSION_ID   = "Mcp-Session-Id"
    JSON_MIME        = "application/json"
    SSE_MIME         = "text/event-stream"
    PROTOCOL_VERSION = "MCP-Protocol-Version"

    getter uri : URI

    @http_client : HTTP::Client?
    @session_id : String?
    @done : Channel(Bool)

    def self.from_uri(url : String) : self
      uri = URI.parse(url)
      new(uri)
    end

    def initialize(@uri : URI)
      super()
      @done = Channel(Bool).new
    end

    def initialize(url : String)
      initialize(URI.parse(url))
    end

    def start
      # Transport is stateless — initialization happens on first send.
      # The HTTP client is created lazily on first use.
    end

    def send(message : MCP::Protocol::JSONRPCMessage)
      client = @http_client ||= HTTP::Client.new(@uri)
      raise "Transport closed" if @done.closed?

      json_body = message.to_json
      headers = build_headers

      response = client.post(@uri.request_target, headers: headers, body: json_body)

      handle_response(response, message)
    rescue ex : IO::Error
      raise ex
    end

    private def build_headers : HTTP::Headers
      hdr = HTTP::Headers.new
      hdr["Content-Type"] = JSON_MIME
      hdr["Accept"] = "#{JSON_MIME}, #{SSE_MIME}"
      if sid = @session_id
        hdr[MCP_SESSION_ID] = sid
      end
      hdr
    end

    private def handle_response(response : HTTP::Client::Response, sent_message : MCP::Protocol::JSONRPCMessage)
      status = response.status_code

      # Capture session ID from any response header
      if sid = response.headers[MCP_SESSION_ID]?
        @session_id = sid
      end

      # 202 Accepted / 204 No Content → return (notification/no body expected)
      if status == 202 || status == 204
        return
      end

      # Empty success body on notification → treat as accepted
      body = response.body || ""
      if response.success? && body.empty? && sent_message.is_a?(MCP::Protocol::JSONRPCNotification)
        return
      end

      # Error status
      unless response.success?
        raise "HTTP #{status}: #{body}"
      end

      # Parse JSON body
      unless body.empty?
        msg = MCP::Protocol::JSONRPCMessage.from_json(body)
        _on_message.call(msg)
      end
    end

    def close
      @done.close

      # Attempt session cleanup via DELETE (best-effort, 5s timeout)
      if sid = @session_id
        spawn do
          client = @http_client
          if client
            hdr = HTTP::Headers.new
            hdr[MCP_SESSION_ID] = sid
            client.delete(@uri.request_target, headers: hdr) rescue nil
          end
        end
      end

      @http_client.try &.close rescue nil
      _on_close.call
    end
  end
end
