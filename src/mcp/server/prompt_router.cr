# Name-based router for MCP prompt handlers with enable/disable support.
#
# Same pattern as `ToolRouter`, adapted for prompt handler signatures
# (`GetPromptRequestParams -> GetPromptResult`).  See `Server#prompt_router`
# for the integrated view.

module MCP::Server
  class PromptRouter
    alias PromptHandler = MCP::Protocol::GetPromptRequestParams -> MCP::Protocol::GetPromptResult

    @handlers = {} of String => PromptHandler
    @disabled = Set(String).new

    def add_prompt(name : String, handler : PromptHandler)
      @handlers[name] = handler
    end

    def remove_prompt(name : String)
      @handlers.delete(name)
      @disabled.delete(name)
    end

    def enable(name : String)
      @disabled.delete(name)
    end

    def disable(name : String)
      @disabled.add(name) if @handlers.has_key?(name)
    end

    def has_prompt?(name : String) : Bool
      @handlers.has_key?(name)
    end

    # Dispatch a prompt call by name.  Raises `KeyError` if unknown or disabled.
    def call(name : String, params : MCP::Protocol::GetPromptRequestParams) : MCP::Protocol::GetPromptResult
      handler = @handlers[name]? || raise KeyError.new("Prompt not found: #{name}")
      raise KeyError.new("Prompt disabled: #{name}") if @disabled.includes?(name)
      handler.call(params)
    end
  end
end
