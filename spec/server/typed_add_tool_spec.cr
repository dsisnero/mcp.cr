require "../spec_helper"

struct GreetInput
  include JSON::Serializable
  property name : String
  property lang : String?

  def initialize(@name : String, @lang : String? = nil)
  end
end

struct GreetOutput
  include JSON::Serializable
  property greeting : String

  def initialize(@greeting : String)
  end
end

describe MCP::Server::Server do
  it "add_tool with typed handler auto-generates input schema" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new.with_tools)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("greet", "Greets someone",
      ->(input : GreetInput) : MCP::Protocol::CallToolResult {
        MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("Hello #{input.name}")] of MCP::Protocol::ContentBlock)
      }
    )

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    response = Channel(MCP::Protocol::JSONRPCMessage).new(1)
    client_transport.on_message { |msg| response.send(msg) }

    spawn { server.connect(server_transport) }
    Fiber.yield

    # Verify the schema is exposed via tools/list
    client_transport.send(MCP::Protocol::ListToolsRequest.new)
    list = response.receive.as(MCP::Protocol::JSONRPCResponse).result.as(MCP::Protocol::ListToolsResult)

    tool = list.tools.first
    tool.name.should eq("greet")
    tool.input_schema.properties.should_not be_nil
    tool.input_schema.properties.try(&.has_key?("name")).should be_true

    # Verify calling the tool with typed args works
    client_transport.send(MCP::Protocol::CallToolRequest.new(
      name: "greet",
      arguments: {"name" => JSON::Any.new("World"), "lang" => JSON::Any.new("en")}
    ))
    call_result = response.receive.as(MCP::Protocol::JSONRPCResponse).result.as(MCP::Protocol::CallToolResult)

    call_result.content.first.as(MCP::Protocol::TextContentBlock).text.should contain("Hello World")
  end
end
