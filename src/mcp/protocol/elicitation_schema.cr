# MCP 2025-06-18 elicitation schema: top-level object container.
#
# Ported from Rust rmcp `model::elicitation_schema::ElicitationSchema`.
# Holds a map of `PrimitiveSchema` properties and an optional `required` list.
# Use `ElicitationSchema.builder` to start the fluent builder.
#
# ```
# schema = MCP::Protocol::ElicitationSchema.builder
#   .required_email("email")
#   .required_integer("age", 0_i64, 150_i64)
#   .optional_bool("newsletter", false)
#   .title("User registration")
#   .description("Collect user details")
#   .build
#
# schema.to_json
# # => {"type":"object","title":"User registration",
# #     "properties":{"email":{...},"age":{...},"newsletter":{...}},
# #     "required":["email","age"]}
# ```
#
# The resulting JSON can be passed as the `requested_schema` argument to
# `ElicitRequestParams`, enabling structured user input collection in MCP
# elicitation flows.

require "./string_schema"
require "./number_schema"
require "./integer_schema"
require "./boolean_schema"
require "./enum_schema"
require "./primitive_schema"

module MCP::Protocol
  # Top-level elicitation schema wrapper.
  struct ElicitationSchema
    include JSON::Serializable

    getter type : String = "object"

    @[JSON::Field(key: "title", emit_null: false)]
    getter title : String?

    @[JSON::Field(key: "description", emit_null: false)]
    getter description : String?

    # Property definitions — must be primitive types only per MCP spec.
    getter properties : Hash(String, PrimitiveSchema)

    # List of property names that are required.
    @[JSON::Field(key: "required", emit_null: false)]
    getter required : Array(String)?

    def initialize(@properties = Hash(String, PrimitiveSchema).new, @required = nil,
                   @title = nil, @description = nil)
    end

    # Start the fluent builder.
    def self.builder
      ElicitationSchemaBuilder.new
    end
  end

  # Fluent builder for `ElicitationSchema`.
  #
  # Convenience methods auto-wrap each primitive schema type:
  #
  # ```
  # builder.required_email("email")         # StringSchema with format: "email"
  # builder.required_integer("age", 0, 150) # IntegerSchema with range 0..150
  # builder.optional_bool("opt_in", false)  # BooleanSchema, default false
  # ```
  #
  # Call `build` when all properties are added.
  class ElicitationSchemaBuilder
    @properties = Hash(String, PrimitiveSchema).new
    @required = [] of String
    @title : String?
    @description : String?

    def title(val : String) : self
      @title = val
      self
    end

    def description(val : String) : self
      @description = val
      self
    end

    # Add a required plain string property.
    def required_string(name : String) : self
      @required << name
      @properties[name] = PrimitiveSchema.new(StringSchema.new)
      self
    end

    # Add an optional plain string property.
    def optional_string(name : String) : self
      @properties[name] = PrimitiveSchema.new(StringSchema.new)
      self
    end

    # Add a required email-format string property.
    def required_email(name : String) : self
      @required << name
      @properties[name] = PrimitiveSchema.new(StringSchema.new.email)
      self
    end

    # Add a required integer property with inclusive range.
    def required_integer(name : String, min : Int64, max : Int64) : self
      @required << name
      @properties[name] = PrimitiveSchema.new(IntegerSchema.new.range(min, max))
      self
    end

    # Add an optional integer property with inclusive range.
    def optional_integer(name : String, min : Int64, max : Int64) : self
      @properties[name] = PrimitiveSchema.new(IntegerSchema.new.range(min, max))
      self
    end

    # Add a required boolean property.
    def required_bool(name : String) : self
      @required << name
      @properties[name] = PrimitiveSchema.new(BooleanSchema.new)
      self
    end

    # Add an optional boolean property with a default.
    def optional_bool(name : String, default : Bool) : self
      @properties[name] = PrimitiveSchema.new(BooleanSchema.new.with_default(default))
      self
    end

    # Finalize and produce the schema.  Empty `required` is omitted.
    def build : ElicitationSchema
      ElicitationSchema.new(@properties, @required.empty? ? nil : @required, @title, @description)
    end
  end
end
