module MCP::Protocol
  struct NumberSchema
    include JSON::Serializable

    getter type : String = "number"

    @[JSON::Field(key: "title", emit_null: false)]
    getter title : String?

    @[JSON::Field(key: "description", emit_null: false)]
    getter description : String?

    @[JSON::Field(key: "minimum", emit_null: false)]
    getter minimum : Float64?

    @[JSON::Field(key: "maximum", emit_null: false)]
    getter maximum : Float64?

    @[JSON::Field(key: "default", emit_null: false)]
    getter default : Float64?

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

    def range(min : Float64, max : Float64) : self
      raise ArgumentError.new("minimum must be <= maximum") if min > max
      @minimum = min
      @maximum = max
      self
    end

    def with_default(val : Float64) : self
      @default = val
      self
    end
  end
end
