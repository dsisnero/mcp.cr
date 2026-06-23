module MCP::Protocol
  struct BooleanSchema
    include JSON::Serializable

    getter type : String = "boolean"

    @[JSON::Field(key: "title", emit_null: false)]
    getter title : String?

    @[JSON::Field(key: "description", emit_null: false)]
    getter description : String?

    @[JSON::Field(key: "default", emit_null: false)]
    getter default : Bool?

    def initialize(@title = nil, @description = nil, @default = nil)
    end

    def title(val : String) : self
      @title = val
      self
    end

    def description(val : String) : self
      @description = val
      self
    end

    def with_default(val : Bool) : self
      @default = val
      self
    end
  end
end
