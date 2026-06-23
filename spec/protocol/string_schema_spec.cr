require "../spec_helper"

describe MCP::Protocol::StringSchema do
  it "serializes the type field" do
    s = MCP::Protocol::StringSchema.new
    s.to_json.should contain("\"type\":\"string\"")
  end

  it "includes an optional title" do
    s = MCP::Protocol::StringSchema.new.title("My Title")
    s.to_json.should contain("\"title\":\"My Title\"")
  end

  it "includes an optional description" do
    s = MCP::Protocol::StringSchema.new.description("Some desc")
    s.to_json.should contain("\"description\":\"Some desc\"")
  end

  it "includes min and max length" do
    s = MCP::Protocol::StringSchema.new.length(1, 100)
    json = s.to_json
    json.should contain("\"minLength\":1")
    json.should contain("\"maxLength\":100")
  end

  it "includes a format" do
    s = MCP::Protocol::StringSchema.new.email
    json = s.to_json
    json.should contain("\"type\":\"string\"")
    json.should contain("\"format\":\"email\"")
  end

  it "includes a default value" do
    s = MCP::Protocol::StringSchema.new.with_default("hello")
    s.to_json.should contain("\"default\":\"hello\"")
  end

  it "omits nil fields from serialization" do
    s = MCP::Protocol::StringSchema.new
    json = s.to_json
    json.should_not contain("title")
    json.should_not contain("minLength")
  end

  it "raises when min > max" do
    expect_raises(ArgumentError, "minLength must be <= maxLength") do
      MCP::Protocol::StringSchema.new.length(10, 1)
    end
  end

  it "supports all standard formats" do
    MCP::Protocol::StringSchema.new.email.to_json.should contain("\"email\"")
    MCP::Protocol::StringSchema.new.uri.to_json.should contain("\"uri\"")
    MCP::Protocol::StringSchema.new.date.to_json.should contain("\"date\"")
    MCP::Protocol::StringSchema.new.date_time.to_json.should contain("\"date-time\"")
  end
end
