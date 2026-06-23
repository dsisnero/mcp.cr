module MCP::Protocol
  struct ConstTitle
    include JSON::Serializable

    @[JSON::Field(key: "const")]
    getter const : String
    getter title : String

    def initialize(@const, @title)
    end
  end

  struct EnumSchema
    include JSON::Serializable

    getter type : String
    @[JSON::Field(key: "title", emit_null: false)]
    getter title : String?
    @[JSON::Field(key: "description", emit_null: false)]
    getter description : String?
    @[JSON::Field(key: "enum", emit_null: false)]
    getter enum : Array(String)?
    @[JSON::Field(key: "oneOf", emit_null: false)]
    getter one_of : Array(ConstTitle)?
    @[JSON::Field(key: "minItems", emit_null: false)]
    getter min_items : Int64?
    @[JSON::Field(key: "maxItems", emit_null: false)]
    getter max_items : Int64?
    @[JSON::Field(key: "default", emit_null: false)]
    getter default : JSON::Any?

    def initialize(@type : String = "string", @title : String? = nil, @description : String? = nil,
                   @enum : Array(String)? = nil, @one_of : Array(ConstTitle)? = nil,
                   @min_items : Int64? = nil, @max_items : Int64? = nil, @default : JSON::Any? = nil)
    end

    def self.builder(values : Array(String))
      EnumSchemaBuilder.new(values)
    end
  end

  class EnumSchemaBuilder
    @values : Array(String)
    @titled = false
    @multi = false
    @title : String?
    @description : String?
    @min_items : Int64?
    @max_items : Int64?
    @default : String?

    def initialize(@values)
    end

    def titled : self
      @titled = true
      self
    end

    def multi_select : self
      @multi = true
      self
    end

    def title(val : String) : self
      @title = val
      self
    end

    def description(val : String) : self
      @description = val
      self
    end

    def min_items(val : Int64) : self
      @min_items = val
      self
    end

    def max_items(val : Int64) : self
      @max_items = val
      self
    end

    def with_default(val : String) : self
      raise ArgumentError.new("default value must be in enum values") unless @values.includes?(val)
      @default = val
      self
    end

    def build : EnumSchema
      if @multi
        EnumSchema.new(
          type: "array",
          title: @title,
          description: @description,
          one_of: @titled ? @values.map { |v| ConstTitle.new(const: v, title: v) } : nil,
          enum: @titled ? nil : @values,
          min_items: @min_items,
          max_items: @max_items,
          default: @default ? JSON.parse([@default].to_json) : nil
        )
      elsif @titled
        EnumSchema.new(
          type: "string",
          title: @title,
          description: @description,
          one_of: @values.map { |v| ConstTitle.new(const: v, title: v) },
          default: @default ? JSON.parse(@default.to_json) : nil
        )
      else
        EnumSchema.new(
          type: "string",
          title: @title,
          description: @description,
          enum: @values,
          default: @default ? JSON.parse(@default.to_json) : nil
        )
      end
    end
  end
end
