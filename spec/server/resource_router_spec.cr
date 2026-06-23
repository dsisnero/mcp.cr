require "../spec_helper"

describe MCP::Server::ResourceRouter do
  it "dispatches a resource by uri" do
    router = MCP::Server::ResourceRouter.new

    router.add_resource("file:///test", ->(_params : MCP::Protocol::ReadResourceRequestParams) {
      MCP::Protocol::ReadResourceResult.new(
        [MCP::Protocol::TextResourceContents.new(uri: "file:///test", text: "hello", mime_type: "text/plain")] of MCP::Protocol::ResourceContents
      )
    })

    result = router.call("file:///test", MCP::Protocol::ReadResourceRequestParams.new("file:///test"))
    result.should be_a(MCP::Protocol::ReadResourceResult)
  end

  it "raises when calling an unknown resource" do
    router = MCP::Server::ResourceRouter.new
    expect_raises(KeyError, "Resource not found: unknown") do
      router.call("unknown", MCP::Protocol::ReadResourceRequestParams.new("unknown"))
    end
  end

  it "removes a resource" do
    router = MCP::Server::ResourceRouter.new

    router.add_resource("file:///test", ->(_params : MCP::Protocol::ReadResourceRequestParams) {
      MCP::Protocol::ReadResourceResult.new(
        [MCP::Protocol::TextResourceContents.new(uri: "file:///test", text: "hello", mime_type: "text/plain")] of MCP::Protocol::ResourceContents
      )
    })

    router.remove_resource("file:///test")
    expect_raises(KeyError, "Resource not found: file:///test") do
      router.call("file:///test", MCP::Protocol::ReadResourceRequestParams.new("file:///test"))
    end
  end

  it "returns true when checking a registered resource" do
    router = MCP::Server::ResourceRouter.new
    router.add_resource("file:///test", ->(_params : MCP::Protocol::ReadResourceRequestParams) {
      MCP::Protocol::ReadResourceResult.new(
        [MCP::Protocol::TextResourceContents.new(uri: "file:///test", text: "hello", mime_type: "text/plain")] of MCP::Protocol::ResourceContents
      )
    })
    router.has_resource?("file:///test").should be_true
    router.has_resource?("unknown").should be_false
  end
end
