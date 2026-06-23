require "../spec_helper"
require "http/client"

describe MCP::Client::SseClientTransport do
  it "receives SSE events as JSON-RPC messages" do
    server = HTTP::Server.new do |ctx|
      case {ctx.request.method, ctx.request.path}
      when {"GET", "/sse"}
        ctx.response.content_type = "text/event-stream"
        ctx.response.status = HTTP::Status::OK
        ctx.response << "event: message\n"
        ctx.response << "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n\n"
        ctx.response.close
      else
        ctx.response.status = HTTP::Status::NOT_FOUND
      end
    end

    addr = server.bind_tcp("127.0.0.1", 0)
    port = addr.port
    spawn { server.listen }
    Fiber.yield

    received = Channel(MCP::Protocol::JSONRPCMessage).new(1)
    transport = MCP::Client::SseClientTransport.new("http://127.0.0.1:#{port}/sse")
    transport.on_message { |msg| received.send(msg) }
    transport.start

    msg = received.receive
    msg.should be_a(MCP::Protocol::JSONRPCNotification)
    msg.as(MCP::Protocol::JSONRPCNotification).method.should eq("notifications/initialized")

    transport.close
    server.close
  end
end
