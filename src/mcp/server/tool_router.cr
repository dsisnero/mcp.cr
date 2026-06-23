module MCP::Server
  class ToolRouter
    @handlers = {} of String => MCP::Protocol::CallToolRequestParams -> MCP::Protocol::CallToolResult
    @disabled = Set(String).new

    alias ToolHandler = MCP::Protocol::CallToolRequestParams -> MCP::Protocol::CallToolResult

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
      @disabled.add(name) if @handlers.has_key?(name)
    end

    def has_tool?(name : String) : Bool
      @handlers.has_key?(name)
    end

    def call(name : String, params : MCP::Protocol::CallToolRequestParams) : MCP::Protocol::CallToolResult
      handler = @handlers[name]? || raise KeyError.new("Tool not found: #{name}")
      raise KeyError.new("Tool disabled: #{name}") if @disabled.includes?(name)
      handler.call(params)
    end
  end
end
