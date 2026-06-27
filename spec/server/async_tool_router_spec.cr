require "../spec_helper"

describe MCP::Server::ToolRouter do
  describe "async tools" do
    it "dispatches an async tool call by name" do
      router = MCP::Server::ToolRouter.new

      router.add_tool_async("async_greet") do |params, extra|
        channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)

        spawn do
          contents = [] of MCP::Protocol::ContentBlock
          contents << MCP::Protocol::TextContentBlock.new("async hello #{params.name}")
          channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(
            value: MCP::Protocol::CallToolResult.new(contents)
          ))
          channel.close
        end

        channel
      end

      params = MCP::Protocol::CallToolRequestParams.new("async_greet")
      result = router.call("async_greet", params)
      result.should be_a(MCP::Protocol::CallToolResult)
      text = result.content[0].as?(MCP::Protocol::TextContentBlock)
      text.not_nil!.text.should eq("async hello async_greet")
    end

    it "raises when calling an unknown async tool" do
      router = MCP::Server::ToolRouter.new
      expect_raises(KeyError, "Tool not found: unknown") do
        router.call("unknown", MCP::Protocol::CallToolRequestParams.new(name: "unknown"))
      end
    end

    it "raises when an async tool is disabled" do
      router = MCP::Server::ToolRouter.new

      router.add_tool_async("async_greet") do |params, extra|
        channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)
        spawn do
          contents = [] of MCP::Protocol::ContentBlock
          contents << MCP::Protocol::TextContentBlock.new("hello")
          channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(
            value: MCP::Protocol::CallToolResult.new(contents)
          ))
          channel.close
        end
        channel
      end

      router.disable("async_greet")
      expect_raises(KeyError, "Tool disabled: async_greet") do
        router.call("async_greet", MCP::Protocol::CallToolRequestParams.new(name: "async_greet"))
      end
    end

    it "enables a previously disabled async tool" do
      router = MCP::Server::ToolRouter.new

      router.add_tool_async("async_greet") do |params, extra|
        channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)
        spawn do
          contents = [] of MCP::Protocol::ContentBlock
          contents << MCP::Protocol::TextContentBlock.new("hello #{params.name}")
          channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(
            value: MCP::Protocol::CallToolResult.new(contents)
          ))
          channel.close
        end
        channel
      end

      router.disable("async_greet")
      router.enable("async_greet")
      result = router.call("async_greet", MCP::Protocol::CallToolRequestParams.new("async_greet"))
      result.should be_a(MCP::Protocol::CallToolResult)
    end

    it "removes an async tool" do
      router = MCP::Server::ToolRouter.new

      router.add_tool_async("async_greet") do |params, extra|
        channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)
        spawn do
          channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(
            value: MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hello")] of MCP::Protocol::ContentBlock)
          ))
          channel.close
        end
        channel
      end

      router.remove_tool("async_greet")
      expect_raises(KeyError, "Tool not found: async_greet") do
        router.call("async_greet", MCP::Protocol::CallToolRequestParams.new(name: "async_greet"))
      end
    end

    it "returns true when checking a registered async tool" do
      router = MCP::Server::ToolRouter.new
      router.add_tool_async("async_greet") do |params, extra|
        channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)
        spawn do
          channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(
            value: MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hello")] of MCP::Protocol::ContentBlock)
          ))
          channel.close
        end
        channel
      end
      router.has_tool?("async_greet").should be_true
      router.has_tool?("unknown").should be_false
    end

    it "reports error from async tool in router" do
      router = MCP::Server::ToolRouter.new

      router.add_tool_async("failing") do |_params, _extra|
        channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)
        spawn do
          channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(
            error: Exception.new("async router failure")
          ))
          channel.close
        end
        channel
      end

      expect_raises(Exception, /async router failure/) do
        router.call("failing", MCP::Protocol::CallToolRequestParams.new("failing"))
      end
    end
  end
end
