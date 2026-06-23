module MCP::Server
  class ResourceRouter
    alias ResourceHandler = MCP::Protocol::ReadResourceRequestParams -> MCP::Protocol::ReadResourceResult

    @handlers = {} of String => ResourceHandler

    def add_resource(uri : String, handler : ResourceHandler)
      @handlers[uri] = handler
    end

    def remove_resource(uri : String)
      @handlers.delete(uri)
    end

    def has_resource?(uri : String) : Bool
      @handlers.has_key?(uri)
    end

    def call(uri : String, params : MCP::Protocol::ReadResourceRequestParams) : MCP::Protocol::ReadResourceResult
      handler = @handlers[uri]? || raise KeyError.new("Resource not found: #{uri}")
      handler.call(params)
    end
  end
end
