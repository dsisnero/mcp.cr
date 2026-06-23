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

    def to_json(builder : JSON::Builder)
      @raw.to_json(builder)
    end
  end
end
