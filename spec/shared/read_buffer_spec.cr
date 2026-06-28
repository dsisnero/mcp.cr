require "../spec_helper"

describe MCP::Shared::ReadBuffer do
  it "should have no messages after initialization" do
    buffer = MCP::Shared::ReadBuffer.new
    buffer.read_message.should be_nil
  end

  it "should only yield a message after a newline" do
    buffer = MCP::Shared::ReadBuffer.new
    msg = MCP::Protocol::JSONRPCNotification.new("foobar")
    buffer.append(msg.to_json)
    buffer.read_message.should be_nil
    buffer.append("\n")
    result = buffer.read_message
    result.should_not be_nil
    result.to_json.should eq(msg.to_json)
    buffer.read_message.should be_nil
  end

  it "should skip empty lines" do
    buffer = MCP::Shared::ReadBuffer.new
    buffer.append("\n")
    buffer.read_message.should be_nil
  end

  it "should be reusable after clearning" do
    buffer = MCP::Shared::ReadBuffer.new
    msg = MCP::Protocol::JSONRPCNotification.new("foobar")
    buffer.append(msg.to_json)
    buffer.clear
    buffer.read_message.should be_nil
    buffer.append(msg.to_json)
    buffer.append("\n")
    result = buffer.read_message
    result.should_not be_nil
    result.to_json.should eq(msg.to_json)
    buffer.read_message.should be_nil
  end

  it "does not parse a partial second message using the first message newline" do
    buffer = MCP::Shared::ReadBuffer.new

    first = MCP::Protocol::JSONRPCResponse.new(
      id: 1_i64,
      result: MCP::Protocol::InitializeResult.new(
        protocol_version: "2025-06-18",
        capabilities: MCP::Protocol::ServerCapabilities.new,
        server_info: MCP::Protocol::Implementation.new(name: "test", version: "0.0.1")
      )
    )

    second = MCP::Protocol::JSONRPCResponse.new(
      id: 2_i64,
      result: MCP::Protocol::ListToolsResult.new(
        tools: [
          MCP::Protocol::Tool.new(
            name: "tool",
            description: "x" * 10_000,
            input_schema: MCP::Protocol::Tool::Input.new(
              properties: {"files" => JSON.parse(%({"type":"array","items":{"type":"string"}}))},
              required: ["files"]
            )
          ),
        ]
      )
    )

    buffer.append(first.to_json)
    buffer.append("\n")
    buffer.read_message.to_json.should eq(first.to_json)

    partial_second = second.to_json[0, 8_000]
    buffer.append(partial_second)
    buffer.read_message.should be_nil

    buffer.append(second.to_json[8_000..])
    buffer.append("\n")
    buffer.read_message.to_json.should eq(second.to_json)
    buffer.read_message.should be_nil
  end
end
