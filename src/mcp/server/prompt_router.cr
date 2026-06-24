# Name-based router for MCP prompt handlers with enable/disable support.
#
# Same pattern as `ToolRouter`, adapted for prompt handler signatures.
# All internal state uses `Sync::XMap` — safe for concurrent use.

require "sync-map/xmap"

module MCP::Server
  class PromptRouter
    alias PromptHandler = MCP::Protocol::GetPromptRequestParams -> MCP::Protocol::GetPromptResult

    @handlers = Sync::XMap(String, PromptHandler).new
    @disabled = Sync::XMap(String, Bool).new

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
      @disabled[name] = true if @handlers.has_key?(name)
    end

    def has_prompt?(name : String) : Bool
      @handlers.has_key?(name)
    end

    def call(name : String, params : MCP::Protocol::GetPromptRequestParams) : MCP::Protocol::GetPromptResult
      handler = @handlers[name]? || raise KeyError.new("Prompt not found: #{name}")
      raise KeyError.new("Prompt disabled: #{name}") if @disabled.has_key?(name)
      handler.call(params)
    end
  end
end
