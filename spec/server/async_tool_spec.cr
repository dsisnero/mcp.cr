require "../spec_helper"
require "wait_group"

describe MCP::Server::Server do
  describe "add_tool_async" do
    it "registers an async tool and calls it" do
      server_options = MCP::Server::ServerOptions.new(
        MCP::Server::ServerCapabilities.new(
          tools: MCP::Server::ServerCapabilities.new.with_tools.tools
        )
      )
      impl = MCP::Protocol::Implementation.new(name: "async-tool server", version: "1.0")
      server = MCP::Server::Server.new(impl, server_options)

      client = MCP::Client::Client.new(
        client_info: MCP::Protocol::Implementation.new("async-tool client", "1.0"),
        client_options: MCP::Client::ClientOptions.new(
          capabilities: MCP::Protocol::ClientCapabilities.new
        )
      )

      client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

      wg = WaitGroup.new(2)

      spawn do
        server.connect(server_transport)
        wg.done
      end
      spawn do
        client.connect(client_transport)
        wg.done
      end

      wg.wait

      server.add_tool_async("greet", "Greet async", MCP::Protocol::Tool::Input.new) do |params, extra|
        channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)

        spawn do
          sleep 10.milliseconds
          contents = [] of MCP::Protocol::ContentBlock
          contents << MCP::Protocol::TextContentBlock.new("async hello #{params.name}")
          channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(
            value: MCP::Protocol::CallToolResult.new(contents)
          ))
          channel.close
        end

        channel
      end

      result = client.call_tool("greet", Hash(String, JSON::Any).new).as(MCP::Protocol::CallToolResult)
      result.content.size.should eq(1)
      text = result.content[0].as?(MCP::Protocol::TextContentBlock)
      text.should_not be_nil
      text.not_nil!.text.should eq("async hello greet")
    end

    it "returns is_error from an async tool that signals error" do
      server_options = MCP::Server::ServerOptions.new(
        MCP::Server::ServerCapabilities.new(
          tools: MCP::Server::ServerCapabilities.new.with_tools.tools
        )
      )
      impl = MCP::Protocol::Implementation.new(name: "async-tool server", version: "1.0")
      server = MCP::Server::Server.new(impl, server_options)

      client = MCP::Client::Client.new(
        client_info: MCP::Protocol::Implementation.new("async-tool client", "1.0"),
        client_options: MCP::Client::ClientOptions.new(
          capabilities: MCP::Protocol::ClientCapabilities.new
        )
      )

      client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

      wg = WaitGroup.new(2)

      spawn do
        server.connect(server_transport)
        wg.done
      end
      spawn do
        client.connect(client_transport)
        wg.done
      end

      wg.wait

      server.add_tool_async("failing", "Failing async", MCP::Protocol::Tool::Input.new) do |_params, _extra|
        channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)

        spawn do
          sleep 10.milliseconds
          contents = [] of MCP::Protocol::ContentBlock
          contents << MCP::Protocol::TextContentBlock.new("tool failed")
          channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(
            value: MCP::Protocol::CallToolResult.new(contents, is_error: true)
          ))
          channel.close
        end

        channel
      end

      result = client.call_tool("failing", Hash(String, JSON::Any).new).as(MCP::Protocol::CallToolResult)
      result.is_error.should be_true
      result.content.first.as(MCP::Protocol::TextContentBlock).text.should eq("tool failed")
    end
  end
end
