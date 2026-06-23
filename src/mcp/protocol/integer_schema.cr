# MCP 2025-06-18 elicitation schema: integer property.
#
# Ported from Rust rmcp `model::elicitation_schema::IntegerSchema`.
# Same builder pattern as `NumberSchema`, using `Int64` for
# minimum/maximum/default.

module MCP::Protocol
  struct IntegerSchema
    include JSON::Serializable

    getter type : String = "integer"

    @[JSON::Field(key: "title", emit_null: false)]
    getter title : String?

    @[JSON::Field(key: "description", emit_null: false)]
    getter description : String?

    @[JSON::Field(key: "minimum", emit_null: false)]
    getter minimum : Int64?

    @[JSON::Field(key: "maximum", emit_null: false)]
    getter maximum : Int64?

    @[JSON::Field(key: "default", emit_null: false)]
    getter default : Int64?

    def initialize(@title = nil, @description = nil, @minimum = nil, @maximum = nil, @default = nil)
    end

    def title(val : String) : self
      @title = val
      self
    end

    def description(val : String) : self
      @description = val
      self
    end

    # Set minimum and maximum (inclusive).  Raises if `min > max`.
    def range(min : Int64, max : Int64) : self
      raise ArgumentError.new("minimum must be <= maximum") if min > max
      @minimum = min
      @maximum = max
      self
    end

    def with_default(val : Int64) : self
      @default = val
      self
    end
  end
end
