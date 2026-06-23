# URI-based router for MCP resource handlers.
#
# Matches resources by exact URI and dispatches to the registered
# handler (`ReadResourceRequestParams -> ReadResourceResult`).
# See `Server#resource_router` for the integrated view.

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

    # Dispatch by exact URI.  Raises `KeyError` if unknown.
    def call(uri : String, params : MCP::Protocol::ReadResourceRequestParams) : MCP::Protocol::ReadResourceResult
      handler = @handlers[uri]? || raise KeyError.new("Resource not found: #{uri}")
      handler.call(params)
    end
  end
end
