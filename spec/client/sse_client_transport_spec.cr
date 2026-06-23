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

  it "extracts endpoint URL from an `event: endpoint` control frame" do
    post_path = "/messages"

    server = HTTP::Server.new do |ctx|
      case {ctx.request.method, ctx.request.path}
      when {"GET", "/sse"}
        ctx.response.content_type = "text/event-stream"
        ctx.response.status = HTTP::Status::OK
        ctx.response << "event: endpoint\n"
        ctx.response << "data: /messages\n\n"
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
    msg.as(MCP::Protocol::JSONRPCNotification).method.should eq("notifications/initialized")

    transport.close
    server.close
  end

  it "sends a client-to-server message via POST" do
    got_post = Channel(MCP::Protocol::JSONRPCMessage).new(1)

    server = HTTP::Server.new do |ctx|
      case {ctx.request.method, ctx.request.path}
      when {"GET", "/sse"}
        ctx.response.content_type = "text/event-stream"
        ctx.response.status = HTTP::Status::OK
        ctx.response << "event: endpoint\n"
        ctx.response << "data: /messages\n\n"
        ctx.response << "event: message\n"
        ctx.response << "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n\n"
        ctx.response.close
      when {"POST", "/messages"}
        body = ctx.request.body.try(&.gets_to_end) || ""
        msg = MCP::Protocol::JSONRPCMessage.from_json(body)
        got_post.send(msg)
        ctx.response.status = HTTP::Status::OK
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

    # Wait for endpoint to be extracted (the server response includes it before message)
    resp = received.receive
    resp.should be_a(MCP::Protocol::JSONRPCResponse)

    # Send a message via POST
    req = MCP::Protocol::PingRequest.new
    transport.send(req)

    sent = got_post.receive
    sent.should be_a(MCP::Protocol::JSONRPCRequest)

    transport.close
    server.close
  end

  it "uses base URL from GET when constructing the POST URL" do
    got_post = Channel(MCP::Protocol::JSONRPCMessage).new(1)

    server = HTTP::Server.new do |ctx|
      case {ctx.request.method, ctx.request.path}
      when {"GET", "/sse"}
        ctx.response.content_type = "text/event-stream"
        ctx.response.status = HTTP::Status::OK
        ctx.response << "event: endpoint\n"
        ctx.response << "data: /messages\n\n"
        ctx.response << "event: message\n"
        ctx.response << "data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}\n\n"
        ctx.response.close
      when {"POST", "/messages"}
        body = ctx.request.body.try(&.gets_to_end) || ""
        msg = MCP::Protocol::JSONRPCMessage.from_json(body)
        got_post.send(msg)
        ctx.response.status = HTTP::Status::OK
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

    resp = received.receive
    resp.should be_a(MCP::Protocol::JSONRPCResponse)

    req = MCP::Protocol::PingRequest.new
    transport.send(req)

    sent = got_post.receive
    sent.should be_a(MCP::Protocol::JSONRPCRequest)

    transport.close
    server.close
  end

  it "reconnects when the SSE stream ends" do
    get_count = Channel(Int32).new(2)

    server = HTTP::Server.new do |ctx|
      case {ctx.request.method, ctx.request.path}
      when {"GET", "/sse"}
        n = get_count.receive
        ctx.response.content_type = "text/event-stream"
        ctx.response.status = HTTP::Status::OK
        if n == 0
          ctx.response << "event: endpoint\n"
          ctx.response << "data: /messages\n\n"
          ctx.response << "event: message\n"
          ctx.response << "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n\n"
        else
          ctx.response << "event: message\n"
          ctx.response << "data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}\n\n"
        end
        ctx.response.close
      else
        ctx.response.status = HTTP::Status::NOT_FOUND
      end
    end

    addr = server.bind_tcp("127.0.0.1", 0)
    port = addr.port
    spawn { server.listen }
    Fiber.yield

    get_count.send(0)
    get_count.send(1)

    received = Channel(MCP::Protocol::JSONRPCMessage).new(2)
    transport = MCP::Client::SseClientTransport.new("http://127.0.0.1:#{port}/sse")
    transport.on_message { |msg| received.send(msg) }
    transport.start

    first = received.receive
    first.should be_a(MCP::Protocol::JSONRPCResponse)

    second = received.receive
    second.should be_a(MCP::Protocol::JSONRPCResponse)

    transport.close
    server.close
  end
end
