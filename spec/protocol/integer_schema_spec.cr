require "../spec_helper"

describe MCP::Protocol::IntegerSchema do
  it "serializes the type field" do
    MCP::Protocol::IntegerSchema.new.to_json.should contain("\"type\":\"integer\"")
  end

  it "includes title, description, min, max, default" do
    s = MCP::Protocol::IntegerSchema.new.title("Age").description("User age").range(0, 150).with_default(25)
    json = s.to_json
    json.should contain("\"title\":\"Age\"")
    json.should contain("\"minimum\":0")
    json.should contain("\"maximum\":150")
    json.should contain("\"default\":25")
  end

  it "raises when min > max" do
    expect_raises(ArgumentError, "minimum must be <= maximum") do
      MCP::Protocol::IntegerSchema.new.range(10_i64, 1_i64)
    end
  end

  it "omits nil fields" do
    json = MCP::Protocol::IntegerSchema.new.to_json
    json.should_not contain("minimum")
    json.should_not contain("title")
  end
end
