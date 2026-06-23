require "../spec_helper"

describe MCP::Protocol::BooleanSchema do
  it "serializes the type field" do
    MCP::Protocol::BooleanSchema.new.to_json.should contain("\"type\":\"boolean\"")
  end

  it "includes title, description, default" do
    s = MCP::Protocol::BooleanSchema.new.title("Opt-in").description("Subscribe").with_default(false)
    json = s.to_json
    json.should contain("\"title\":\"Opt-in\"")
    json.should contain("\"default\":false")
  end

  it "omits nil fields" do
    json = MCP::Protocol::BooleanSchema.new.to_json
    json.should_not contain("title")
  end
end
