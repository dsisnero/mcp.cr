require "../spec_helper"

describe MCP::Server::ToolRouter do
  it "dispatches a tool call by name" do
    router = MCP::Server::ToolRouter.new

    router.add_tool("greet", ->(_params : MCP::Protocol::CallToolRequestParams) {
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hello")] of MCP::Protocol::ContentBlock)
    })

    result = router.call("greet", MCP::Protocol::CallToolRequestParams.new("greet"))
    result.should be_a(MCP::Protocol::CallToolResult)
  end

  it "raises when calling an unknown tool" do
    router = MCP::Server::ToolRouter.new
    expect_raises(KeyError, "Tool not found: unknown") do
      router.call("unknown", MCP::Protocol::CallToolRequestParams.new(name: "unknown"))
    end
  end

  it "raises when a tool is disabled" do
    router = MCP::Server::ToolRouter.new

    router.add_tool("greet", ->(_params : MCP::Protocol::CallToolRequestParams) {
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hello")] of MCP::Protocol::ContentBlock)
    })

    router.disable("greet")
    expect_raises(KeyError, "Tool disabled: greet") do
      router.call("greet", MCP::Protocol::CallToolRequestParams.new(name: "greet"))
    end
  end

  it "enables a previously disabled tool" do
    router = MCP::Server::ToolRouter.new

    router.add_tool("greet", ->(_params : MCP::Protocol::CallToolRequestParams) {
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hello")] of MCP::Protocol::ContentBlock)
    })

    router.disable("greet")
    router.enable("greet")
    result = router.call("greet", MCP::Protocol::CallToolRequestParams.new("greet"))
    result.should be_a(MCP::Protocol::CallToolResult)
  end

  it "removes a tool" do
    router = MCP::Server::ToolRouter.new

    router.add_tool("greet", ->(_params : MCP::Protocol::CallToolRequestParams) {
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hello")] of MCP::Protocol::ContentBlock)
    })

    router.remove_tool("greet")
    expect_raises(KeyError, "Tool not found: greet") do
      router.call("greet", MCP::Protocol::CallToolRequestParams.new(name: "greet"))
    end
  end

  it "returns true when checking a registered tool" do
    router = MCP::Server::ToolRouter.new
    router.add_tool("greet", ->(_params : MCP::Protocol::CallToolRequestParams) {
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hello")] of MCP::Protocol::ContentBlock)
    })
    router.has_tool?("greet").should be_true
    router.has_tool?("unknown").should be_false
  end
end
