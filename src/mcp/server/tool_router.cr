# Name-based router for MCP tool handlers with enable/disable support.
#
# Provides dispatch, inspection, and dynamic enable/disable over
# registered tools.  All internal state uses `Sync::XMap` — safe
# for concurrent use by multiple fibers.
#
# ```
# router = MCP::Server::ToolRouter.new
# router.add_tool("greet", ->(params : CallToolRequestParams) { ... })
# router.has_tool?("greet") # => true
# router.disable("greet")
# router.enable("greet")
# router.call("greet", params)
# ```

require "sync-map/xmap"

module MCP::Server
  class ToolRouter
    alias ToolHandler = MCP::Protocol::CallToolRequestParams -> MCP::Protocol::CallToolResult
    alias AsyncToolHandler = (MCP::Protocol::CallToolRequestParams, MCP::Shared::RequestHandlerExtra) -> Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult))

    @handlers = Sync::XMap(String, ToolHandler).new
    @disabled = Sync::XMap(String, Bool).new

    def add_tool(name : String, handler : ToolHandler)
      @handlers[name] = handler
    end

    # Register an async tool handler. The handler receives
    # `CallToolRequestParams` and `RequestHandlerExtra` and returns a
    # `Channel(AsyncResult(CallToolResult))`. The router waits on the
    # channel and returns or raises accordingly.
    def add_tool_async(name : String, &handler : AsyncToolHandler)
      extra = MCP::Shared::RequestHandlerExtra.new

      wrapped = ->(params : MCP::Protocol::CallToolRequestParams) {
        result_channel = handler.call(params, extra)

        if cancel_ch = extra.cancel_channel
          select_ch = Channel(Nil).new(1)

          spawn do
            cancel_ch.receive rescue nil
            select_ch.send(nil) rescue nil
          end

          async_result : MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)? = nil
          select
          when async_result = result_channel.receive
          when select_ch.receive
            raise MCP::Protocol::MCPError.new(:invalid_request, "Request cancelled")
          end

          r = async_result.not_nil!
          if r.success?
            r.value.not_nil!
          else
            raise r.error.not_nil!
          end
        else
          async_result = result_channel.receive
          if async_result.success?
            async_result.value.not_nil!
          else
            raise async_result.error.not_nil!
          end
        end
      }

      @handlers[name] = wrapped
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
