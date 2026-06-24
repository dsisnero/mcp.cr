# MCP 2025-06-18 elicitation schema: enum property.
#
# Ported from Rust rmcp `model::elicitation_schema::EnumSchema`.
# Supports three variants:
#
# 1. **Untitled single-select** (`{type: "string", enum: [...], default}`)
#    — a flat list of string values, choose-one.
# 2. **Titled single-select** (`{type: "string", oneOf: [{const, title}], default}`)
#    — each value has a human-readable title.
# 3. **Untitled multi-select** (`{type: "array", ...}`) — choose-many with
#    min/max items.
#
# The builder enforces that `default` is one of the enum values.
#
# ```
# # Untitled single-select
# EnumSchema.builder(["red", "green", "blue"]).with_default("red").build
#
# # Titled single-select
# EnumSchema.builder(["us", "uk"]).titled.with_default("us").build
#
# # Multi-select (untitled)
# EnumSchema.builder(["a", "b", "c"]).multi_select.min_items(1).max_items(3).build
# ```

module MCP::Protocol
  # A `{const, title}` pair used in titled single-select variants.
  struct ConstTitle
    include JSON::Serializable

    @[JSON::Field(key: "const")]
    getter const : String
    getter title : String

    def initialize(@const, @title)
    end
  end

  # The unified enum schema, representing any of the three variants above.
  # Construct via `EnumSchema.builder(values)`.
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

    # Start building a schema from the given string values.
    def self.builder(values : Array(String))
      EnumSchemaBuilder.new(values)
    end
  end

  # Fluent builder for `EnumSchema`.
  #
  # Call `titled` before `build` to produce a `oneOf` variant;
  # call `multi_select` to produce an `array`-typed multi-select.
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

    # Produce a titled variant (`oneOf`) instead of untitled (`enum`).
    def titled : self
      @titled = true
      self
    end

    # Switch to multi-select mode (type "array" with minItems/maxItems).
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

    # Set the default value.  Must be one of the enum values.
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
