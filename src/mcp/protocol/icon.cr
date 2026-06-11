module MCP::Protocol
  struct Icon
    include JSON::Serializable

    getter src : String
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String?
    getter sizes : String?
    getter theme : String?

    def initialize(@src, @mime_type = nil, @sizes = nil, @theme = nil)
    end
  end
end
