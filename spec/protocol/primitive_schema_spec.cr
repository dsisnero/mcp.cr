require "../spec_helper"

describe MCP::Protocol::PrimitiveSchema do
  it "wraps a StringSchema" do
    s = MCP::Protocol::PrimitiveSchema.new(MCP::Protocol::StringSchema.new.title("Name"))
    json = s.to_json
    json.should contain("\"type\":\"string\"")
    json.should contain("\"title\":\"Name\"")
  end

  it "wraps a NumberSchema" do
    s = MCP::Protocol::PrimitiveSchema.new(MCP::Protocol::NumberSchema.new.range(0.0, 100.0))
    json = s.to_json
    json.should contain("\"type\":\"number\"")
    json.should contain("\"minimum\":0.0")
  end

  it "wraps an IntegerSchema" do
    s = MCP::Protocol::PrimitiveSchema.new(MCP::Protocol::IntegerSchema.new.with_default(42_i64))
    json = s.to_json
    json.should contain("\"type\":\"integer\"")
    json.should contain("\"default\":42")
  end

  it "wraps a BooleanSchema" do
    s = MCP::Protocol::PrimitiveSchema.new(MCP::Protocol::BooleanSchema.new.with_default(true))
    json = s.to_json
    json.should contain("\"type\":\"boolean\"")
    json.should contain("\"default\":true")
  end

  it "wraps an EnumSchema" do
    es = MCP::Protocol::EnumSchema.builder(["a", "b"]).build
    s = MCP::Protocol::PrimitiveSchema.new(es)
    json = s.to_json
    json.should contain("\"type\":\"string\"")
    json.should contain("\"enum\":[\"a\",\"b\"]")
  end
end
