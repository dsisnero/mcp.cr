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

  it "returns nil for a fragmented second message (no stale newline)" do
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
        ] of MCP::Protocol::Tool
      )
    )

    buffer.append(first.to_json)
    buffer.append("\n")
    msg = buffer.read_message
    msg.should_not be_nil
    msg.to_json.should eq(first.to_json)

    # Append only the first 8000 bytes of the second message (no trailing newline)
    second_json = second.to_json
    partial = second_json[0, 8_000]
    buffer.append(partial)

    # Must return nil — the newline detection must NOT see the consumed \n from
    # the first message
    result = buffer.read_message
    result.should be_nil

    # Append the rest + newline — must return the complete second message
    buffer.append(second_json[8_000..])
    buffer.append("\n")
    result = buffer.read_message
    result.should_not be_nil
    result.to_json.should eq(second.to_json)
  end
end
