require "../spec_helper"
require "wait_group"

# Multi-threaded stress spec for Gap 10 — thread-safe registration maps.
#
# Run under true parallelism:
#   crystal spec spec/server/registration_mt_spec.cr -Dpreview_mt -Dexecution_context
#
# On a bare `Hash` backing the registration maps this races: concurrent
# rehash/resize from parallel writers corrupts the table (lost entries,
# crashes, or wrong final counts). With `Sync::Map` every mutation is
# serialized under the writer lock, so the final state is deterministic.
describe "MCP::Server::Server concurrent registration" do
  {% if flag?(:execution_context) %}
    it "registers tools from many parallel fibers without losing entries" do
      server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new.with_tools)
      impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
      server = MCP::Server::Server.new(impl, server_options)

      workers = 8
      per_worker = 250
      ctx = Fiber::ExecutionContext::Parallel.new("registrars", workers)
      wg = WaitGroup.new(workers)

      workers.times do |w|
        ctx.spawn do
          per_worker.times do |i|
            name = "tool-#{w}-#{i}"
            server.add_tool(name, "desc", MCP::Protocol::Tool::Input.new) do |_|
              MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
            end
          end
          wg.done
        end
      end
      wg.wait

      total = workers * per_worker
      server.@tools.size.should eq(total)
      workers.times do |w|
        per_worker.times do |i|
          server.tool_registered?("tool-#{w}-#{i}").should be_true
        end
      end
    end

    it "interleaves concurrent add and remove without corruption" do
      server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new.with_tools)
      impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
      server = MCP::Server::Server.new(impl, server_options)

      workers = 8
      per_worker = 250
      ctx = Fiber::ExecutionContext::Parallel.new("churners", workers)
      wg = WaitGroup.new(workers)

      workers.times do |w|
        ctx.spawn do
          per_worker.times do |i|
            name = "tool-#{w}-#{i}"
            server.add_tool(name, "desc", MCP::Protocol::Tool::Input.new) do |_|
              MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
            end
            server.remove_tool(name)
          end
          wg.done
        end
      end
      wg.wait

      server.@tools.size.should eq(0)
    end
  {% else %}
    pending "requires -Dpreview_mt -Dexecution_context for true parallelism"
  {% end %}
end
