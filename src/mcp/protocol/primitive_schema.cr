# Union wrapper for all MCP 2025-06-18 primitive elicitation schema types.
#
# Wraps `StringSchema`, `NumberSchema`, `IntegerSchema`, `BooleanSchema`,
# or `EnumSchema` for use as property values inside an `ElicitationSchema`.
#
# Serialization is flat — the wrapped schema's JSON is emitted directly
# (no additional nesting).

module MCP::Protocol
  struct PrimitiveSchema
    @raw : JSON::Any

    def initialize(schema : StringSchema)
      @raw = JSON.parse(schema.to_json)
    end

    def initialize(schema : NumberSchema)
      @raw = JSON.parse(schema.to_json)
    end

    def initialize(schema : IntegerSchema)
      @raw = JSON.parse(schema.to_json)
    end

    def initialize(schema : BooleanSchema)
      @raw = JSON.parse(schema.to_json)
    end

    def initialize(schema : EnumSchema)
      @raw = JSON.parse(schema.to_json)
    end

    # Serializes the wrapped schema's JSON directly.
    def to_json(builder : JSON::Builder)
      @raw.to_json(builder)
    end
  end
end
