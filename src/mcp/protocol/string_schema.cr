# MCP 2025-06-18 elicitation schema: string property.
#
# Ported from Rust rmcp `model::elicitation_schema::StringSchema`.
# Provides a builder pattern for constructing MCP-compliant string
# schema definitions with optional title, description, length
# constraints, format (email/uri/date/date-time), and default value.
#
# ```
# require "mcp"
#
# schema = MCP::Protocol::StringSchema.new
#   .title("Email address")
#   .description("Your primary email")
#   .email
#   .with_default("user@example.com")
#
# schema.to_json
# # => {"type":"string","title":"Email address",
# #     "description":"Your primary email","format":"email",
# #     "default":"user@example.com"}
# ```

module MCP::Protocol
  # String format types allowed by the MCP specification.
  enum StringFormat
    Email
    Uri
    Date
    DateTime
  end

  # Schema definition for string properties.
  #
  # Fields map to JSON Schema `string` with the MCP-required camelCase
  # keys.  Nil fields are omitted from serialization.
  struct StringSchema
    include JSON::Serializable

    getter type : String = "string"

    # Optional human-readable title.
    @[JSON::Field(key: "title", emit_null: false)]
    getter title : String?

    # Optional human-readable description.
    @[JSON::Field(key: "description", emit_null: false)]
    getter description : String?

    # Minimum string length (inclusive).
    @[JSON::Field(key: "minLength", emit_null: false)]
    getter min_length : Int32?

    # Maximum string length (inclusive).
    @[JSON::Field(key: "maxLength", emit_null: false)]
    getter max_length : Int32?

    # String format — one of "email", "uri", "date", "date-time".
    @[JSON::Field(key: "format", emit_null: false)]
    getter format : String?

    # Default value for the property.
    @[JSON::Field(key: "default", emit_null: false)]
    getter default : String?

    def initialize(@title = nil, @description = nil, @min_length = nil, @max_length = nil, @format = nil, @default = nil)
    end

    # Set the optional title.
    def title(val : String) : self
      @title = val
      self
    end

    # Set the optional description.
    def description(val : String) : self
      @description = val
      self
    end

    # Set both minimum and maximum length.  Raises if `min > max`.
    def length(min : Int32, max : Int32) : self
      raise ArgumentError.new("minLength must be <= maxLength") if min > max
      @min_length = min
      @max_length = max
      self
    end

    # Set the format from a `StringFormat` enum value.
    def format(fmt : StringFormat) : self
      @format = case fmt
                when StringFormat::Email    then "email"
                when StringFormat::Uri      then "uri"
                when StringFormat::Date     then "date"
                when StringFormat::DateTime then "date-time"
                end
      self
    end

    # Set a default string value.
    def with_default(val : String) : self
      @default = val
      self
    end

    # Convenience: pre-configures the `email` format.
    def email : self
      format(StringFormat::Email)
    end

    # Convenience: pre-configures the `uri` format.
    def uri : self
      format(StringFormat::Uri)
    end

    # Convenience: pre-configures the `date` format (YYYY-MM-DD).
    def date : self
      format(StringFormat::Date)
    end

    # Convenience: pre-configures the `date-time` format (ISO 8601).
    def date_time : self
      format(StringFormat::DateTime)
    end
  end
end
