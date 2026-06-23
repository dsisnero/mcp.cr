require "../spec_helper"

describe MCP::Protocol::EnumSchema do
  it "builds an untitled single-select enum" do
    schema = MCP::Protocol::EnumSchema.builder(["red", "green", "blue"])
      .with_default("red")
      .build

    json = schema.to_json
    json.should contain("\"type\":\"string\"")
    json.should contain("\"enum\":[\"red\",\"green\",\"blue\"]")
    json.should contain("\"default\":\"red\"")
  end

  it "builds a titled single-select enum" do
    schema = MCP::Protocol::EnumSchema.builder(["us", "uk"])
      .titled
      .with_default("us")
      .build

    json = schema.to_json
    json.should contain("\"type\":\"string\"")
    json.should contain("\"oneOf\"")
    json.should contain("\"const\":\"us\"")
    json.should contain("\"title\":\"us\"")
  end

  it "builds an untitled multi-select enum" do
    schema = MCP::Protocol::EnumSchema.builder(["a", "b", "c"])
      .multi_select
      .min_items(1).max_items(3)
      .build

    json = schema.to_json
    json.should contain("\"type\":\"array\"")
    json.should contain("\"enum\":[\"a\",\"b\",\"c\"]")
    json.should contain("\"minItems\":1")
    json.should contain("\"maxItems\":3")
  end

  it "raises when default value is not in enum" do
    expect_raises(ArgumentError, "default value must be in enum values") do
      MCP::Protocol::EnumSchema.builder(["a", "b"]).with_default("z")
    end
  end

  it "includes optional title and description" do
    schema = MCP::Protocol::EnumSchema.builder(["x", "y"])
      .title("Options")
      .description("Pick one")
      .build

    json = schema.to_json
    json.should contain("\"title\":\"Options\"")
    json.should contain("\"description\":\"Pick one\"")
  end
end
