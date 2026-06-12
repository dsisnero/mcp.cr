require "../spec_helper"
require "http/client"
require "http/request"
require "http/server"

describe MCP::Server::StreamableHttpServerTransport do
  it "should start and close cleanly" do
    transport = MCP::Server::StreamableHttpServerTransport.new(stateful: false)

    did_close = false

    transport.on_close { did_close = true }

    transport.start
    did_close.should be_false
    transport.close
    did_close.should be_true
  end

  it "should initialize with stateful mode" do
    transport = MCP::Server::StreamableHttpServerTransport.new(stateful: true)
    transport.start

    transport.session_id.should be_nil
    transport.close
  end

  it "should initialize with stateless mode" do
    transport = MCP::Server::StreamableHttpServerTransport.new(stateful: false)
    transport.start

    transport.session_id.should be_nil
    transport.close
  end

  it "should handle message callbacks" do
    transport = MCP::Server::StreamableHttpServerTransport.new
    received_msg = nil

    transport.on_message { |msg| received_msg = msg }

    transport.start

    # Test that message handler can be called
    received_msg.should be_nil
    transport.close
  end

  # RED-GREEN race condition tests for the JSON response path.
  # Without the channel-based fix in handle_post_request, the spawned handler
  # fiber would write to call.response AFTER the HTTP handler returned, causing
  # the response to arrive empty or truncated.

  it "writes JSON response before handle_post_request returns (Ping)" do
    body_io = IO::Memory.new
    request = HTTP::Request.new("POST", "/mcp",
      headers: HTTP::Headers{
        "Accept"       => "application/json, text/event-stream",
        "Content-Type" => "application/json",
      },
      body: MCP::Protocol::PingRequest.new.to_json)

    context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(body_io))

    transport = MCP::Server::StreamableHttpServerTransport.new(enable_json_response: true)
    transport.start

    server = MCP::Server::Server.new(
      MCP::Protocol::Implementation.new(name: "test", version: "1.0"),
      MCP::Server::ServerOptions.new(
        MCP::Server::ServerCapabilities.new
      )
    )
    server.connect(transport)

    transport.handle_post_request(context)

    context.response.close
    body = body_io.to_s

    body.should contain("\"result\"")
    body.should contain("\"id\"")
    body.should contain("2.0")
    body.should_not be_empty
  end

  it "writes JSON response before handle_post_request returns with slow handler" do
    body_io = IO::Memory.new
    slow_req = MCP::Protocol::CallToolRequest.new("slow-tool", Hash(String, JSON::Any).new)
    request = HTTP::Request.new("POST", "/mcp",
      headers: HTTP::Headers{
        "Accept"       => "application/json, text/event-stream",
        "Content-Type" => "application/json",
      },
      body: slow_req.to_json)

    context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(body_io))

    transport = MCP::Server::StreamableHttpServerTransport.new(enable_json_response: true)
    transport.start

    server = MCP::Server::Server.new(
      MCP::Protocol::Implementation.new(name: "test", version: "1.0"),
      MCP::Server::ServerOptions.new(
        MCP::Server::ServerCapabilities.new.with_tools
      )
    )

    server.add_tool("slow-tool", "A slow tool", MCP::Protocol::Tool::Input.new) do |_req|
      sleep(100.milliseconds)
      contents = [MCP::Protocol::TextContentBlock.new("done")] of MCP::Protocol::ContentBlock
      MCP::Protocol::CallToolResult.new(contents)
    end

    server.connect(transport)

    transport.handle_post_request(context)

    context.response.close
    body = body_io.to_s

    body.should contain("\"content\"")
    body.should contain("done")
    body.should_not be_empty
  end

  it "does not block for notification-only POSTs" do
    body_io = IO::Memory.new
    notification = MCP::Protocol::InitializedNotification.new
    request = HTTP::Request.new("POST", "/mcp",
      headers: HTTP::Headers{
        "Accept"       => "application/json, text/event-stream",
        "Content-Type" => "application/json",
      },
      body: notification.to_json)

    context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(body_io))

    transport = MCP::Server::StreamableHttpServerTransport.new(enable_json_response: true)
    transport.start

    server = MCP::Server::Server.new(
      MCP::Protocol::Implementation.new(name: "test", version: "1.0"),
      MCP::Server::ServerOptions.new(
        MCP::Server::ServerCapabilities.new
      )
    )
    server.connect(transport)

    transport.handle_post_request(context)

    context.response.status_code.should eq(HTTP::Status::ACCEPTED.code)
  end

  it "handles multiple requests in a batch POST" do
    body_io = IO::Memory.new
    messages = [
      MCP::Protocol::PingRequest.new,
      MCP::Protocol::PingRequest.new,
    ]
    body = "[#{messages.map(&.to_json).join(",")}]"
    request = HTTP::Request.new("POST", "/mcp",
      headers: HTTP::Headers{
        "Accept"       => "application/json, text/event-stream",
        "Content-Type" => "application/json",
      },
      body: body)

    context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(body_io))

    transport = MCP::Server::StreamableHttpServerTransport.new(enable_json_response: true)
    transport.start

    server = MCP::Server::Server.new(
      MCP::Protocol::Implementation.new(name: "test", version: "1.0"),
      MCP::Server::ServerOptions.new(
        MCP::Server::ServerCapabilities.new
      )
    )
    server.connect(transport)

    transport.handle_post_request(context)

    context.response.close
    body = body_io.to_s

    body.should contain("[")
    body.should contain("]")
    body.should_not be_empty
  end
end
