require "../spec_helper"
require "wait_group"

# Multi-threaded stress spec for client protocol correlation maps.
#
# Run under true parallelism:
#   crystal spec spec/client/client_concurrency_mt_spec.cr -Dpreview_mt -Dexecution_context
#
# On bare `Hash` backing the response/progress/canceller maps, concurrent
# call_tool from multiple fibers races: rehash corruption, lost/misrouted
# replies, or double-completion hanging the caller fiber.
describe MCP::Client::Client do
  {% if flag?(:execution_context) %}
    it "handles concurrent call_tool from many parallel fibers" do
      server_options = MCP::Server::ServerOptions.new(
        MCP::Server::ServerCapabilities.new.with_tools.with_resources
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

      workers = 8
      per_worker = 50
      ctx = Fiber::ExecutionContext::Parallel.new("callers", workers)
      wg = WaitGroup.new(workers)

      workers.times do |w|
        ctx.spawn do
          per_worker.times do |i|
            result = client.call_tool("echo", {"value" => JSON::Any.new("w#{w}-#{i}")})
            result.should be_a(MCP::Protocol::CallToolResult)
          end
          wg.done
        end
      end
      wg.wait
    end

    it "handles concurrent call_tool under timeout pressure" do
      server_options = MCP::Server::ServerOptions.new(
        MCP::Server::ServerCapabilities.new.with_tools
      )
      impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
      server = MCP::Server::Server.new(impl, server_options)

      barrier = Channel(Nil).new(8)
      release = Channel(Nil).new(1)

      server.add_tool("gated", "Waits for release", MCP::Protocol::Tool::Input.new) do |_|
        barrier.send(nil)
        release.receive
        MCP::Protocol::CallToolResult.new(
          [MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock
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

      workers = 8
      ctx = Fiber::ExecutionContext::Parallel.new("callers", workers)
      wg = WaitGroup.new(workers)

      workers.times do |w|
        ctx.spawn do
          result = client.call_tool("gated", {} of String => JSON::Any)
          result.should be_a(MCP::Protocol::CallToolResult)
          wg.done
        end
      end

      8.times { barrier.receive }
      release.send(nil)
      wg.wait
    end
  {% else %}
    pending "requires -Dpreview_mt -Dexecution_context for true parallelism"
  {% end %}
end
