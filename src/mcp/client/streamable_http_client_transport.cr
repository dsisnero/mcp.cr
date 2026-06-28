# MCP Streamable HTTP client transport: connects to a remote MCP server
# over a single streamable HTTP endpoint using an actor-fiber pattern.
#
# An actor fiber owns the HTTP client and session state.  Outbound
# messages are queued via a channel; the actor fiber POSTs them and
# dispatches inbound JSON-RPC responses through the inherited
# `on_message` callback.  This keeps `send` non-blocking — the protocol
# layer waits for responses on its own channels, not on the HTTP call.
#
# Session management: a `Mcp-Session-Id` header returned by the
# server on the initialize response is captured and replayed on all
# subsequent requests. If no session ID is returned, the transport
# operates in stateless mode.
#
# On `close`, the done channel is closed, signalling the actor fiber
# to drain its inbox, clean up the session (DELETE best-effort), and
# call `_on_close`.
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

    @session_id : String?
    @started = false
    @done = Channel(Bool).new
    @inbox = Channel(MCP::Protocol::JSONRPCMessage).new(16)

    def self.from_uri(url : String) : self
      uri = URI.parse(url)
      new(uri)
    end

    def initialize(@uri : URI)
      super()
    end

    def initialize(url : String)
      initialize(URI.parse(url))
    end

    # Spawns the actor fiber that owns all transport state (HTTP client,
    # session ID) and runs the for-select event loop.
    def start
      return if @started
      @started = true
      spawn(name: "streamable-http-client") { run_loop }
    end

    # Enqueue a message for the actor fiber to POST.  Non-blocking.
    def send(message : MCP::Protocol::JSONRPCMessage)
      raise "Transport closed" if @done.closed?
      @inbox.send(message)
    end

    # Close the done channel.  The actor fiber will drain the inbox,
    # clean up the session, and call _on_close.  If start was never
    # called, close immediately.
    def close
      if @done.closed?
        return
      end
      @done.close
      _on_close.call unless @started
    end

    # ---- Actor fiber ---------------------------------------------------

    private def run_loop
      client = HTTP::Client.new(@uri)

      begin
        loop do
          select
          when msg = @inbox.receive?
            break unless msg
            process(client, msg)
          when @done.receive?
            break
          end
        end

        drain_inbox(client)
      rescue ex
        _on_error.call(ex)
      end

      cleanup(client)
    end

    private def drain_inbox(client : HTTP::Client)
      while msg = @inbox.receive?
        process(client, msg) if msg
      end
    end

    private def process(client : HTTP::Client, message : MCP::Protocol::JSONRPCMessage)
      json_body = message.to_json
      headers = build_headers

      response = client.post(@uri.request_target, headers: headers, body: json_body)
      handle_response(response, message)
    rescue ex
      _on_error.call(ex)
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
        _on_error.call(Exception.new("HTTP #{status}: #{body}"))
        return
      end

      # Parse JSON body and dispatch
      unless body.empty?
        msg = MCP::Protocol::JSONRPCMessage.from_json(body)
        _on_message.call(msg)
      end
    end

    private def cleanup(client : HTTP::Client)
      # Best-effort session cleanup via DELETE
      if sid = @session_id
        hdr = HTTP::Headers.new
        hdr[MCP_SESSION_ID] = sid
        client.delete(@uri.request_target, headers: hdr) rescue nil
      end

      client.close rescue nil
      _on_close.call
    end
  end
end
