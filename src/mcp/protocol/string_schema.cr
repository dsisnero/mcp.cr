module MCP::Protocol
  enum StringFormat
    Email
    Uri
    Date
    DateTime
  end

  struct StringSchema
    include JSON::Serializable

    getter type : String = "string"

    @[JSON::Field(key: "title", emit_null: false)]
    getter title : String?

    @[JSON::Field(key: "description", emit_null: false)]
    getter description : String?

    @[JSON::Field(key: "minLength", emit_null: false)]
    getter min_length : Int32?

    @[JSON::Field(key: "maxLength", emit_null: false)]
    getter max_length : Int32?

    @[JSON::Field(key: "format", emit_null: false)]
    getter format : String?

    @[JSON::Field(key: "default", emit_null: false)]
    getter default : String?

    def initialize(@title = nil, @description = nil, @min_length = nil, @max_length = nil, @format = nil, @default = nil)
    end

    def title(val : String) : self
      @title = val
      self
    end

    def description(val : String) : self
      @description = val
      self
    end

    def length(min : Int32, max : Int32) : self
      raise ArgumentError.new("minLength must be <= maxLength") if min > max
      @min_length = min
      @max_length = max
      self
    end

    def format(fmt : StringFormat) : self
      @format = case fmt
                when StringFormat::Email    then "email"
                when StringFormat::Uri      then "uri"
                when StringFormat::Date     then "date"
                when StringFormat::DateTime then "date-time"
                end
      self
    end

    def with_default(val : String) : self
      @default = val
      self
    end

    def email : self
      format(StringFormat::Email)
    end

    def uri : self
      format(StringFormat::Uri)
    end

    def date : self
      format(StringFormat::Date)
    end

    def date_time : self
      format(StringFormat::DateTime)
    end
  end
end
