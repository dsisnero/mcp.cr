# Name-based router for MCP tool handlers with enable/disable support.
#
# Provides dispatch, inspection, and dynamic enable/disable over
# registered tools.  Intended for server-side composition —
# see `Server#tool_router` for the integrated view.
#
# ```
# router = MCP::Server::ToolRouter.new
# router.add_tool("greet", ->(params : CallToolRequestParams) { ... })
# router.has_tool?("greet")  # => true
# router.disable("greet")
# router.enable("greet")
# router.call("greet", params)
# ```

module MCP::Server
  class ToolRouter
    alias ToolHandler = MCP::Protocol::CallToolRequestParams -> MCP::Protocol::CallToolResult

    @handlers = {} of String => ToolHandler
    @disabled = Set(String).new

    # Register a tool handler by name.
    def add_tool(name : String, handler : ToolHandler)
      @handlers[name] = handler
    end

    # Remove a tool and its disabled flag.
    def remove_tool(name : String)
      @handlers.delete(name)
      @disabled.delete(name)
    end

    # Re-enable a previously disabled tool.
    def enable(name : String)
      @disabled.delete(name)
    end

    # Disable a tool so that `call` raises `KeyError`.
    def disable(name : String)
      @disabled.add(name) if @handlers.has_key?(name)
    end

    # Check whether a tool is registered.
    def has_tool?(name : String) : Bool
      @handlers.has_key?(name)
    end

    # Dispatch a tool call by name.  Raises `KeyError` if unknown or disabled.
    def call(name : String, params : MCP::Protocol::CallToolRequestParams) : MCP::Protocol::CallToolResult
      handler = @handlers[name]? || raise KeyError.new("Tool not found: #{name}")
      raise KeyError.new("Tool disabled: #{name}") if @disabled.includes?(name)
      handler.call(params)
    end
  end
end
