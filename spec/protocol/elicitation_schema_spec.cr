require "../spec_helper"

describe MCP::Protocol::ElicitationSchema do
  it "has object type" do
    s = MCP::Protocol::ElicitationSchema.builder.build
    s.to_json.should contain("\"type\":\"object\"")
  end

  it "builds a schema with required string and optional integer" do
    s = MCP::Protocol::ElicitationSchema.builder
      .required_string("email")
      .optional_integer("age", 0_i64, 150_i64)
      .build

    json = s.to_json
    json.should contain("\"type\":\"object\"")
    json.should contain("\"email\"")
    json.should contain("\"age\"")
    json.should contain("\"required\":[\"email\"]")
  end

  it "includes optional title and description" do
    s = MCP::Protocol::ElicitationSchema.builder
      .title("User Info")
      .description("Collect user details")
      .required_string("name")
      .build

    json = s.to_json
    json.should contain("\"title\":\"User Info\"")
    json.should contain("\"description\":\"Collect user details\"")
  end

  it "builds with a required email and optional boolean" do
    s = MCP::Protocol::ElicitationSchema.builder
      .required_email("email")
      .optional_bool("newsletter", false)
      .build

    json = s.to_json
    json.should contain("\"email\"")
    json.should contain("\"newsletter\"")
    json.should contain("\"format\":\"email\"")
    json.should contain("\"default\":false")
  end

  it "omits required when empty" do
    s = MCP::Protocol::ElicitationSchema.builder.optional_string("comment").build
    s.to_json.should_not contain("required")
  end
end
