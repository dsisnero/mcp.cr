require "../spec_helper"

describe MCP::Server::PromptRouter do
  it "dispatches a prompt by name" do
    router = MCP::Server::PromptRouter.new

    router.add_prompt("hello", ->(_params : MCP::Protocol::GetPromptRequestParams) {
      MCP::Protocol::GetPromptResult.new(
        [MCP::Protocol::PromptMessage.new(role: MCP::Protocol::Role::Assistant, content: MCP::Protocol::TextContentBlock.new("hello world"))],
        description: "greeting"
      )
    })

    result = router.call("hello", MCP::Protocol::GetPromptRequestParams.new("hello"))
    result.should be_a(MCP::Protocol::GetPromptResult)
  end

  it "raises when calling an unknown prompt" do
    router = MCP::Server::PromptRouter.new
    expect_raises(KeyError, "Prompt not found: unknown") do
      router.call("unknown", MCP::Protocol::GetPromptRequestParams.new("unknown"))
    end
  end

  it "raises when a prompt is disabled" do
    router = MCP::Server::PromptRouter.new

    router.add_prompt("hello", ->(_params : MCP::Protocol::GetPromptRequestParams) {
      MCP::Protocol::GetPromptResult.new(
        [MCP::Protocol::PromptMessage.new(role: MCP::Protocol::Role::Assistant, content: MCP::Protocol::TextContentBlock.new("hello world"))],
        description: "greeting"
      )
    })

    router.disable("hello")
    expect_raises(KeyError, "Prompt disabled: hello") do
      router.call("hello", MCP::Protocol::GetPromptRequestParams.new("hello"))
    end
  end

  it "removes a prompt" do
    router = MCP::Server::PromptRouter.new

    router.add_prompt("hello", ->(_params : MCP::Protocol::GetPromptRequestParams) {
      MCP::Protocol::GetPromptResult.new(
        [MCP::Protocol::PromptMessage.new(role: MCP::Protocol::Role::Assistant, content: MCP::Protocol::TextContentBlock.new("hello world"))],
        description: "greeting"
      )
    })

    router.remove_prompt("hello")
    expect_raises(KeyError, "Prompt not found: hello") do
      router.call("hello", MCP::Protocol::GetPromptRequestParams.new("hello"))
    end
  end

  it "returns true when checking a registered prompt" do
    router = MCP::Server::PromptRouter.new
    router.add_prompt("hello", ->(_params : MCP::Protocol::GetPromptRequestParams) {
      MCP::Protocol::GetPromptResult.new(
        [MCP::Protocol::PromptMessage.new(role: MCP::Protocol::Role::Assistant, content: MCP::Protocol::TextContentBlock.new("hello world"))],
        description: "greeting"
      )
    })
    router.has_prompt?("hello").should be_true
    router.has_prompt?("unknown").should be_false
  end
end
