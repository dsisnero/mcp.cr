require "../spec_helper"

describe MCP::Server::Server do
  it "exposes a tool_router that mirrors registered tools" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new.with_tools)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("greet", "Greets", MCP::Protocol::Tool::Input.new) do |_params|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hi")] of MCP::Protocol::ContentBlock)
    end

    router = server.tool_router
    router.has_tool?("greet").should be_true
    router.has_tool?("unknown").should be_false
  end

  it "tool_router dispatch calls the registered handler" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new.with_tools)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("greet", "Greets", MCP::Protocol::Tool::Input.new) do |_params|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hi")] of MCP::Protocol::ContentBlock)
    end

    result = server.tool_router.call("greet", MCP::Protocol::CallToolRequestParams.new("greet"))
    result.should be_a(MCP::Protocol::CallToolResult)
  end

  it "tool_router supports enable/disable of registered tools" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new.with_tools)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("greet", "Greets", MCP::Protocol::Tool::Input.new) do |_params|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hi")] of MCP::Protocol::ContentBlock)
    end

    server.tool_router.disable("greet")
    expect_raises(KeyError, "Tool disabled: greet") do
      server.tool_router.call("greet", MCP::Protocol::CallToolRequestParams.new("greet"))
    end

    server.tool_router.enable("greet")
    result = server.tool_router.call("greet", MCP::Protocol::CallToolRequestParams.new("greet"))
    result.should be_a(MCP::Protocol::CallToolResult)
  end
end
