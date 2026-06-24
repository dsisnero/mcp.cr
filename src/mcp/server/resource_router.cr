# URI-based router for MCP resource handlers.
#
# Matches resources by exact URI and dispatches to the registered
# handler.  Internal state uses `Sync::XMap` — safe for concurrent use.

require "sync-map/xmap"

module MCP::Server
  class ResourceRouter
    alias ResourceHandler = MCP::Protocol::ReadResourceRequestParams -> MCP::Protocol::ReadResourceResult

    @handlers = Sync::XMap(String, ResourceHandler).new

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
