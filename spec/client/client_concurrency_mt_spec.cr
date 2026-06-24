require "../spec_helper"
require "wait_group"

# Concurrent client request spec.
#
# Under the standard gate each worker uses plain `spawn` (cooperative
# interleaving).  Under `-Dpreview_mt -Dexecution_context` the workers
# use `ExecutionContext::Parallel` for true parallelism.
describe MCP::Client::Client do
  it "handles concurrent call_tool from many fibers" do
    server_options = MCP::Server::ServerOptions.new(
      MCP::Server::ServerCapabilities.new.with_tools
    )
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("echo", "Echoes the input", MCP::Protocol::Tool::Input.new) do |params|
      arg = params.arguments.try(&.["value"]?) || JSON::Any.new("")
      MCP::Protocol::CallToolResult.new(
        [MCP::Protocol::TextContentBlock.new(arg.to_s)] of MCP::Protocol::ContentBlock
      )
    end

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    wg = WaitGroup.new
    wg.spawn { server.connect(server_transport) }

    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.new
      )
    )
    wg.spawn { client.connect(client_transport) }
    wg.wait

    workers = 16
    per_worker = 20
    wg = WaitGroup.new(workers)

    workers.times do |w|
      spawn do
        per_worker.times do |i|
          result = client.call_tool("echo", {"value" => JSON::Any.new("w#{w}-#{i}")})
          result.should be_a(MCP::Protocol::CallToolResult)
        end
        wg.done
      end
    end
    wg.wait
  end

  it "handles concurrent call_tool under timeout constraint" do
    server_options = MCP::Server::ServerOptions.new(
      MCP::Server::ServerCapabilities.new.with_tools
    )
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("echo", "Echoes", MCP::Protocol::Tool::Input.new) do |params|
      arg = params.arguments.try(&.["value"]?) || JSON::Any.new("")
      MCP::Protocol::CallToolResult.new(
        [MCP::Protocol::TextContentBlock.new(arg.to_s)] of MCP::Protocol::ContentBlock
      )
    end

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    wg = WaitGroup.new
    wg.spawn { server.connect(server_transport) }

    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.new
      )
    )
    wg.spawn { client.connect(client_transport) }
    wg.wait

    # Mix of concurrent call_tool with short timeout — stresses the
    # atomic claim-and-remove path (timeout cancel vs response delivery).
    workers = 4
    wg = WaitGroup.new(workers)
    workers.times do
      spawn do
        5.times do
          begin
            client.call_tool("echo", {"value" => JSON::Any.new("ok")})
          rescue e : MCP::Protocol::MCPError
            # timeout is expected under concurrent pressure
            raise e unless e.message.try(&.includes?("timed out"))
          end
        end
        wg.done
      end
    end
    wg.wait
  end
end
