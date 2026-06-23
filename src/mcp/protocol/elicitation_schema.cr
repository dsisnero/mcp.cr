require "./string_schema"
require "./number_schema"
require "./integer_schema"
require "./boolean_schema"
require "./enum_schema"
require "./primitive_schema"

module MCP::Protocol
  struct ElicitationSchema
    include JSON::Serializable

    getter type : String = "object"

    @[JSON::Field(key: "title", emit_null: false)]
    getter title : String?

    @[JSON::Field(key: "description", emit_null: false)]
    getter description : String?

    getter properties : Hash(String, PrimitiveSchema)

    @[JSON::Field(key: "required", emit_null: false)]
    getter required : Array(String)?

    def initialize(@properties = Hash(String, PrimitiveSchema).new, @required = nil,
                   @title = nil, @description = nil)
    end

    def self.builder
      ElicitationSchemaBuilder.new
    end
  end

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

    def required_string(name : String) : self
      @required << name
      @properties[name] = PrimitiveSchema.new(StringSchema.new)
      self
    end

    def optional_string(name : String) : self
      @properties[name] = PrimitiveSchema.new(StringSchema.new)
      self
    end

    def required_email(name : String) : self
      @required << name
      @properties[name] = PrimitiveSchema.new(StringSchema.new.email)
      self
    end

    def required_integer(name : String, min : Int64, max : Int64) : self
      @required << name
      @properties[name] = PrimitiveSchema.new(IntegerSchema.new.range(min, max))
      self
    end

    def optional_integer(name : String, min : Int64, max : Int64) : self
      @properties[name] = PrimitiveSchema.new(IntegerSchema.new.range(min, max))
      self
    end

    def required_bool(name : String) : self
      @required << name
      @properties[name] = PrimitiveSchema.new(BooleanSchema.new)
      self
    end

    def optional_bool(name : String, default : Bool) : self
      @properties[name] = PrimitiveSchema.new(BooleanSchema.new.with_default(default))
      self
    end

    def build : ElicitationSchema
      ElicitationSchema.new(@properties, @required.empty? ? nil : @required, @title, @description)
    end
  end
end
