require "../spec_helper"

describe MCP::Protocol::NumberSchema do
  it "serializes the type field" do
    MCP::Protocol::NumberSchema.new.to_json.should contain("\"type\":\"number\"")
  end

  it "includes optional title and description" do
    s = MCP::Protocol::NumberSchema.new.title("Age").description("User age")
    json = s.to_json
    json.should contain("\"title\":\"Age\"")
    json.should contain("\"description\":\"User age\"")
  end

  it "includes minimum and maximum" do
    s = MCP::Protocol::NumberSchema.new.range(0.0, 100.0)
    json = s.to_json
    json.should contain("\"minimum\":0.0")
    json.should contain("\"maximum\":100.0")
  end

  it "includes a default value" do
    s = MCP::Protocol::NumberSchema.new.with_default(42.5)
    s.to_json.should contain("\"default\":42.5")
  end

  it "raises when min > max" do
    expect_raises(ArgumentError, "minimum must be <= maximum") do
      MCP::Protocol::NumberSchema.new.range(10.0, 1.0)
    end
  end

  it "omits nil fields" do
    s = MCP::Protocol::NumberSchema.new
    json = s.to_json
    json.should_not contain("minimum")
    json.should_not contain("title")
  end
end
