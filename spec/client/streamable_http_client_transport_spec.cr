require "../spec_helper"
require "http/server"

describe MCP::Client::StreamableHttpClientTransport do
  it "creates a transport from a URI" do
    transport = MCP::Client::StreamableHttpClientTransport.from_uri("http://127.0.0.1:8080/mcp")
    transport.should_not be_nil
    transport.should be_a(MCP::Shared::AbstractTransport)
  end

  it "start is a no-op (initialization happens on first send)" do
    transport = MCP::Client::StreamableHttpClientTransport.from_uri("http://127.0.0.1:9999/mcp")
    transport.start
  end

  it "sends a ping and receives a pong through the transport" do
    # A minimal JSON-response mode server
    server = HTTP::Server.new do |ctx|
      if ctx.request.method == "POST"
        content_type = ctx.request.headers["Content-Type"]?
        accept = ctx.request.headers["Accept"]?

        # Validate required headers
        unless content_type && content_type.starts_with?("application/json")
          ctx.response.status = HTTP::Status::BAD_REQUEST
          next
        end
        unless accept && accept.includes?("application/json") && accept.includes?("text/event-stream")
          ctx.response.status = HTTP::Status::NOT_ACCEPTABLE
          next
        end

        body = ctx.request.body.try(&.gets_to_end) || "{}"
        msg = MCP::Protocol::JSONRPCMessage.from_json(body)

        case msg
        when MCP::Protocol::InitializeRequest
          session_id = ctx.request.headers["Mcp-Session-Id"]?
          if session_id
            ctx.response.status = HTTP::Status::BAD_REQUEST
            ctx.response.print %({"jsonrpc":"2.0","error":{"code":-32600,"message":"Already initialized"}})
          else
            ctx.response.content_type = "application/json"
            ctx.response.headers["Mcp-Session-Id"] = "test-session-123"
            result = MCP::Protocol::InitializeResult.new(
              protocol_version: MCP::Protocol::LATEST_PROTOCOL_VERSION,
              capabilities: MCP::Protocol::ServerCapabilities.new,
              server_info: MCP::Protocol::Implementation.new("test", "1.0")
            )
            ctx.response.print MCP::Protocol::JSONRPCResponse.new(
              id: msg.id, result: result
            ).to_json
          end
        when MCP::Protocol::PingRequest
          session_id = ctx.request.headers["Mcp-Session-Id"]?
          if session_id == "test-session-123"
            ctx.response.content_type = "application/json"
            ctx.response.print MCP::Protocol::JSONRPCResponse.new(
              id: msg.id, result: MCP::Protocol::EmptyResult.new
            ).to_json
          else
            ctx.response.status = HTTP::Status::BAD_REQUEST
          end
        when MCP::Protocol::JSONRPCNotification
          ctx.response.status = HTTP::Status::ACCEPTED
        else
          ctx.response.status = HTTP::Status::NOT_FOUND
        end
      else
        ctx.response.status = HTTP::Status::METHOD_NOT_ALLOWED
      end
    end

    addr = server.bind_tcp("127.0.0.1", 0)
    port = addr.port
    spawn { server.listen }
    Fiber.yield

    received = Channel(MCP::Protocol::JSONRPCMessage).new(8)
    transport = MCP::Client::StreamableHttpClientTransport.from_uri("http://127.0.0.1:#{port}/mcp")
    transport.on_message { |msg| received.send(msg) }
    transport.start

    # Initialize handshake
    transport.send(MCP::Protocol::InitializeRequest.new(
      protocol_version: MCP::Protocol::LATEST_PROTOCOL_VERSION,
      capabilities: MCP::Protocol::ClientCapabilities.new,
      client_info: MCP::Protocol::Implementation.new("test-client", "1.0")
    ))
    init_response = received.receive.as(MCP::Protocol::JSONRPCResponse)
    init_response.should_not be_nil

    # Send ping
    transport.send(MCP::Protocol::PingRequest.new)

    # Wait for response
    result = received.receive
    result.should be_a(MCP::Protocol::JSONRPCResponse)

    transport.close
    server.close
  end

  it "handles the initialize handshake and returns JSON responses" do
    server = HTTP::Server.new do |ctx|
      if ctx.request.method == "POST"
        content_type = ctx.request.headers["Content-Type"]?
        accept = ctx.request.headers["Accept"]?
        unless content_type && content_type.starts_with?("application/json")
          ctx.response.status = HTTP::Status::BAD_REQUEST
          next
        end
        unless accept && accept.includes?("application/json") && accept.includes?("text/event-stream")
          ctx.response.status = HTTP::Status::NOT_ACCEPTABLE
          next
        end

        body = ctx.request.body.try(&.gets_to_end) || "{}"
        msg = MCP::Protocol::JSONRPCMessage.from_json(body)

        case msg
        when MCP::Protocol::InitializeRequest
          session_id = ctx.request.headers["Mcp-Session-Id"]?
          if session_id
            ctx.response.status = HTTP::Status::BAD_REQUEST
            ctx.response.print %({"jsonrpc":"2.0","error":{"code":-32600,"message":"Already initialized"}})
          else
            ctx.response.content_type = "application/json"
            ctx.response.headers["Mcp-Session-Id"] = "test-session-456"
            result = MCP::Protocol::InitializeResult.new(
              protocol_version: MCP::Protocol::LATEST_PROTOCOL_VERSION,
              capabilities: MCP::Protocol::ServerCapabilities.new(tools: MCP::Protocol::ServerCapabilities::ToolsCapability.new(list_changed: false)),
              server_info: MCP::Protocol::Implementation.new("test-tools", "1.0")
            )
            ctx.response.print MCP::Protocol::JSONRPCResponse.new(
              id: msg.id, result: result
            ).to_json
          end
        when MCP::Protocol::JSONRPCNotification
          # initialized notification
          ctx.response.status = HTTP::Status::ACCEPTED
        when MCP::Protocol::ListToolsRequest
          session_id = ctx.request.headers["Mcp-Session-Id"]?
          if session_id == "test-session-456"
            ctx.response.content_type = "application/json"
            result = MCP::Protocol::ListToolsResult.new(tools: [] of MCP::Protocol::Tool)
            ctx.response.print MCP::Protocol::JSONRPCResponse.new(
              id: msg.id, result: result
            ).to_json
          else
            ctx.response.status = HTTP::Status::BAD_REQUEST
          end
        else
          ctx.response.status = HTTP::Status::NOT_FOUND
        end
      else
        ctx.response.status = HTTP::Status::METHOD_NOT_ALLOWED
      end
    end

    addr = server.bind_tcp("127.0.0.1", 0)
    port = addr.port
    spawn { server.listen }
    Fiber.yield

    received = Channel(MCP::Protocol::JSONRPCMessage).new(8)
    transport = MCP::Client::StreamableHttpClientTransport.from_uri("http://127.0.0.1:#{port}/mcp")
    transport.on_message { |msg| received.send(msg) }
    transport.start

    # Send init
    transport.send(MCP::Protocol::InitializeRequest.new(
      protocol_version: MCP::Protocol::LATEST_PROTOCOL_VERSION,
      capabilities: MCP::Protocol::ClientCapabilities.new,
      client_info: MCP::Protocol::Implementation.new("test-client", "1.0")
    ))

    init_response = received.receive.as(MCP::Protocol::JSONRPCResponse)
    init_response.should_not be_nil

    # Send initialized notification (fire and forget, accept 202)
    transport.send(MCP::Protocol::InitializedNotification.new)

    # Send tools/list
    transport.send(MCP::Protocol::ListToolsRequest.new)
    list_response = received.receive.as(MCP::Protocol::JSONRPCResponse)
    list_response.should_not be_nil
    list_response.result.should be_a(MCP::Protocol::ListToolsResult)

    transport.close
    server.close
  end

  it "close invokes on_close callback" do
    transport = MCP::Client::StreamableHttpClientTransport.from_uri("http://127.0.0.1:9999/mcp")
    closed = false
    transport.on_close { closed = true }
    transport.close
    closed.should be_true
  end
end
