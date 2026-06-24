# Name-based router for MCP tool handlers with enable/disable support.
#
# Provides dispatch, inspection, and dynamic enable/disable over
# registered tools.  All internal state uses `Sync::XMap` — safe
# for concurrent use by multiple fibers.
#
# ```
# router = MCP::Server::ToolRouter.new
# router.add_tool("greet", ->(params : CallToolRequestParams) { ... })
# router.has_tool?("greet")  # => true
# router.disable("greet")
# router.enable("greet")
# router.call("greet", params)
# ```

require "sync-map/xmap"

module MCP::Server
  class ToolRouter
    alias ToolHandler = MCP::Protocol::CallToolRequestParams -> MCP::Protocol::CallToolResult

    @handlers = Sync::XMap(String, ToolHandler).new
    @disabled = Sync::XMap(String, Bool).new

    def add_tool(name : String, handler : ToolHandler)
      @handlers[name] = handler
    end

    def remove_tool(name : String)
      @handlers.delete(name)
      @disabled.delete(name)
    end

    def enable(name : String)
      @disabled.delete(name)
    end

    def disable(name : String)
      @disabled[name] = true if @handlers.has_key?(name)
    end

    def has_tool?(name : String) : Bool
      @handlers.has_key?(name)
    end

    def call(name : String, params : MCP::Protocol::CallToolRequestParams) : MCP::Protocol::CallToolResult
      handler = @handlers[name]? || raise KeyError.new("Tool not found: #{name}")
      raise KeyError.new("Tool disabled: #{name}") if @disabled.has_key?(name)
      handler.call(params)
    end
  end
end
