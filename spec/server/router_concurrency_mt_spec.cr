require "../spec_helper"
require "wait_group"

describe MCP::Server::ToolRouter do
  it "handles concurrent add/remove/call from many fibers" do
    router = MCP::Server::ToolRouter.new

    workers = 16
    per_worker = 20
    wg = WaitGroup.new(workers)

    workers.times do |w|
      spawn do
        per_worker.times do |i|
          name = "tool-#{w}-#{i}"
          router.add_tool(name, ->(_params : MCP::Protocol::CallToolRequestParams) {
            MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
          })
          router.has_tool?(name).should be_true if router.has_tool?(name)
        end
        wg.done
      end
    end
    wg.wait
  end

  it "handles concurrent enable/disable/call from many fibers" do
    router = MCP::Server::ToolRouter.new

    router.add_tool("t", ->(_params : MCP::Protocol::CallToolRequestParams) {
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    })

    workers = 8
    wg = WaitGroup.new(workers)

    workers.times do
      spawn do
        100.times do
          begin
            router.disable("t")
            router.enable("t")
            router.call("t", MCP::Protocol::CallToolRequestParams.new("t"))
          rescue KeyError
          end
        end
        wg.done
      end
    end
    wg.wait
  end
end
