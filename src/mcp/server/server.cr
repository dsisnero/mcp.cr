require "base64"
require "json"
require "log"
require "sync-map"
require "../shared"

module MCP::Server
  Log = ::Log.for(self)

  alias ServerCapabilities = MCP::Protocol::ServerCapabilities
  alias ClientCapabilities = MCP::Protocol::ClientCapabilities
  alias Implementation = MCP::Protocol::Implementation
  alias ProtocolOptions = MCP::Shared::ProtocolOptions
  alias JSONRPCMessage = MCP::Protocol::JSONRPCMessage
  alias JSONRPCRequest = MCP::Protocol::JSONRPCRequest
  alias JSONRPCResponse = MCP::Protocol::JSONRPCResponse
  alias JSONRPCNotification = MCP::Protocol::JSONRPCNotification

  class ServerOptions < ProtocolOptions
    property capabilities : ServerCapabilities
    property? enforce_strict_capabilities : Bool = true
    property pagination_limit : Int32?

    def initialize(@capabilities, @enforce_strict_capabilities = true, @timeout = Shared::DEFAULT_REQUEST_TIMEOUT, @pagination_limit = nil)
      super(@enforce_strict_capabilities, @timeout)
    end
  end

  class Server < MCP::Shared::Protocol
    getter server_info : Implementation
    getter client_capabilities : ClientCapabilities?
    getter client_version : Implementation?

    @_on_initialized : Proc(Nil) = -> { }
    @_on_close : Proc(Nil) = -> { }
    @_on_logging_level_change : Proc(MCP::Protocol::LoggingLevel, Nil) = ->(level : MCP::Protocol::LoggingLevel) { }

    @tools : Sync::Map(String, RegisteredTool) = Sync::Map(String, RegisteredTool).new
    @prompts : Sync::Map(String, RegisteredPrompt) = Sync::Map(String, RegisteredPrompt).new
    @resources : Sync::Map(String, RegisteredResource) = Sync::Map(String, RegisteredResource).new
    @resource_templates : Sync::Map(String, RegisteredResourceTemplate) = Sync::Map(String, RegisteredResourceTemplate).new
    @subscriptions = Set(String).new
    @completion_handler : (MCP::Protocol::CompleteRequestParams -> MCP::Protocol::CompleteResult)?
    property logging_level : MCP::Protocol::LoggingLevel = MCP::Protocol::LoggingLevel::Info
    getter server_options : ServerOptions

    def initialize(@server_info, @server_options)
      super(@server_options)
      Log.debug { "Initializing MCP server with capabilities: #{capabilities.to_json}" }

      # Core protocol handlers
      request_handler(MCP::Protocol::Initialize) do |request, _|
        handle_initialize(request.as(MCP::Protocol::InitializeRequestParams))
      end

      notification_handler(MCP::Protocol::NotificationsInitialized) do
        @_on_initialized.call
        nil
      end

      # Internal handlers for tools
      if capabilities.tools
        request_handler(MCP::Protocol::ToolsList) { |_, _| handle_list_tools }
        request_handler(MCP::Protocol::ToolsCall) do |request, _|
          handle_call_tool(request.as(MCP::Protocol::CallToolRequestParams))
        end
      end

      # Internal handlers for completion
      if capabilities.completions
        request_handler(MCP::Protocol::CompletionComplete) do |request, _|
          handle_complete(request.as(MCP::Protocol::CompleteRequestParams))
        end
      end

      # Internal handlers for logging
      if capabilities.logging
        request_handler(MCP::Protocol::LoggingSetLevel) do |request, _|
          handle_set_level(request.as(MCP::Protocol::SetLevelRequestParams))
        end
      end

      # Internal handlers for prompts
      if capabilities.prompts
        request_handler(MCP::Protocol::PromptsList) { |_, _| handle_list_prompts }
        request_handler(MCP::Protocol::PromptsGet) do |request, _|
          handle_get_prompt(request.as(MCP::Protocol::GetPromptRequestParams))
        end
      end

      # Internal handlers for resources
      if capabilities.resources
        request_handler(MCP::Protocol::ResourcesList) { |_, _| handle_list_resources }
        request_handler(MCP::Protocol::ResourcesRead) do |request, _|
          handle_read_resource(request.as(MCP::Protocol::ReadResourceRequestParams))
        end
        request_handler(MCP::Protocol::ResourcesTemplatesList) do |_, _|
          handle_list_resource_templates
        end
        request_handler(MCP::Protocol::ResourcesSubscribe) do |request, _|
          handle_subscribe_resource(request.as(MCP::Protocol::SubscribeRequestParams))
        end
        request_handler(MCP::Protocol::ResourcesUnsubscribe) do |request, _|
          handle_unsubscribe_resource(request.as(MCP::Protocol::UnsubscribeRequestParams))
        end
      end
    end

    def capabilities : ServerCapabilities
      self.server_options.capabilities
    end

    def on_initialized(&block : -> Nil)
      old = @_on_initialized
      @_on_initialized = -> {
        old.call
        block.call
      }
    end

    def on_close(&block : -> Nil)
      old = @_on_close
      @_on_close = -> {
        old.call
        block.call
      }
    end

    def on_close
      Log.info { "Server connection closing" }
      @_on_close.call
    end

    def add_tool(name : String, description : String, input_schema : MCP::Protocol::Tool::Input, &handler : MCP::Protocol::CallToolRequestParams -> MCP::Protocol::CallToolResult)
      add_tool(name, description, input_schema, annotations: nil, output_schema: nil, &handler)
    end

    # Auto-generate input schema from a Crystal type using json-schema introspection.
    # The type must include JSON::Serializable.
    def add_tool(name : String, description : String, input_type : T.class,
                 annotations : MCP::Protocol::ToolAnnotations? = nil,
                 output_schema : MCP::Protocol::Tool::Input? = nil,
                 &handler : MCP::Protocol::CallToolRequestParams -> MCP::Protocol::CallToolResult) forall T
      input = MCP::Protocol::Tool::Input.from(input_type)
      add_tool(name, description, input, annotations: annotations, output_schema: output_schema, &handler)
    end

    # Auto-generate both input and output schemas from Crystal types.
    def add_tool(name : String, description : String, input_type : T.class,
                 output_type : U.class,
                 annotations : MCP::Protocol::ToolAnnotations? = nil,
                 &handler : MCP::Protocol::CallToolRequestParams -> MCP::Protocol::CallToolResult) forall T, U
      input = MCP::Protocol::Tool::Input.from(input_type)
      oschema = MCP::Protocol::Tool::Output.from(output_type)
      add_tool(name, description, input, annotations: annotations, output_schema: oschema, &handler)
    end

    def add_tool(name : String, description : String, input_schema : MCP::Protocol::Tool::Input,
                 annotations : MCP::Protocol::ToolAnnotations? = nil,
                 output_schema : MCP::Protocol::Tool::Input? = nil,
                 &handler : MCP::Protocol::CallToolRequestParams -> MCP::Protocol::CallToolResult)
      if capabilities.tools.nil?
        Log.error { " Failed to add tool #{name}: Server does not support tools capability" }
        raise ArgumentError.new("Server does not support tools capability. Enable it in ServerOptions")
      end
      Log.info { "Registering tool #{name}" }
      tool = MCP::Protocol::Tool.new(name, input_schema, description, annotations: annotations, output_schema: output_schema)
      @tools[name] = RegisteredTool.new(tool, handler)
      notify_tool_list_changed
    end

    def add_tools(tools : Array(RegisteredTool))
      if capabilities.tools.nil?
        Log.error { "Failed to add tools: Server does not support tools capability" }
        raise ArgumentError.new("Server does not support tools capability. Enable it in ServerOptions")
      end

      Log.info { "Registering #{tools.size} tools" }
      tools.each do |rtool|
        Log.debug { "Registering tool: #{rtool.tool.name}" }
        @tools[rtool.tool.name] = rtool
      end
      notify_tool_list_changed
    end

    def remove_tool(name : String) : Bool
      if capabilities.tools.nil?
        Log.error { " Failed to remove tool #{name}: Server does not support tools capability" }
        raise ArgumentError.new("Server does not support tools capability.")
      end
      Log.info { "Removing tool #{name}" }
      _, removed = @tools.load_and_delete(name)
      Log.debug {
        removed ? "Tool removed: #{name}" : "Tool not found: #{name}"
      }
      notify_tool_list_changed if removed
      removed
    end

    def remove_tools(tool_names : Array(String)) : Int32
      if capabilities.tools.nil?
        Log.error { " Failed to remove tools: Server does not support tools capability" }
        raise ArgumentError.new("Server does not support tools capability.")
      end

      res = tool_names.map { |name| remove_tool(name) }
      removed = res.count(&.== true)
      Log.info { removed > 0 ? "Removed #{removed} tools" : "No tools were removed" }
      notify_tool_list_changed if removed > 0
      removed
    end

    def add_prompt(prompt : MCP::Protocol::Prompt, &handler : MCP::Protocol::GetPromptRequestParams -> MCP::Protocol::GetPromptResult)
      if capabilities.prompts.nil?
        Log.error { " Failed to add prompt #{prompt.name}: Server does not support prompts capability" }
        raise ArgumentError.new("Server does not support prompts capability.")
      end
      Log.info { "Registering prompt #{prompt.name}" }
      @prompts[prompt.name] = RegisteredPrompt.new(prompt, handler)
      notify_prompt_list_changed
    end

    def add_prompt(name : String, &handler : MCP::Protocol::GetPromptRequestParams -> MCP::Protocol::GetPromptResult)
      add_prompt(name, nil, nil, handler)
    end

    def add_prompt(name : String, description : String?, arguments : Array(MCP::Protocol::PromptArgument)?, &handler : MCP::Protocol::GetPromptRequestParams -> MCP::Protocol::GetPromptResult)
      prompt = MCP::Protocol::Prompt.new(name, description, arguments)
      add_prompt(prompt, handler)
    end

    def add_prompts(prompt_list : Array(RegisteredPrompt))
      if capabilities.prompts.nil?
        Log.error { " Failed to add prompts: Server does not support prompts capability" }
        raise ArgumentError.new("Server does not support prompts capability.")
      end

      prompt_list.each { |rprompt| add_prompt(rprompt.prompt, rprompt.handler) }
      notify_prompt_list_changed
    end

    def remove_prompt(name : String) : Bool
      if capabilities.prompts.nil?
        Log.error { " Failed to remove prompt #{name}: Server does not support prompts capability" }
        raise ArgumentError.new("Server does not support prompts capability.")
      end
      Log.info { "Removing prompt #{name}" }
      _, removed = @prompts.load_and_delete(name)
      Log.debug {
        removed ? "Prompt removed: #{name}" : "Prompt not found: #{name}"
      }
      notify_prompt_list_changed if removed
      removed
    end

    def remove_prompts(names : Array(String)) : Int32
      if capabilities.prompts.nil?
        Log.error { " Failed to add prompts: Server does not support prompts capability" }
        raise ArgumentError.new("Server does not support prompts capability.")
      end
      res = names.map { |name| remove_prompt(name) }
      removed = res.count(&.== true)
      Log.info { removed > 0 ? "Removed #{removed} prompts" : "No prompts were removed" }
      notify_prompt_list_changed if removed > 0
      removed
    end

    def add_resource(uri : String, name : String, description : String, mime_type : String, &handler : MCP::Protocol::ReadResourceRequestParams -> MCP::Protocol::ReadResourceResult)
      if capabilities.resources.nil?
        Log.error { " Failed to add resource #{name}: Server does not support resources capability" }
        raise ArgumentError.new("Server does not support resources capability.")
      end
      Log.info { "Registering resource #{name} #{uri}" }
      @resources[uri] = RegisteredResource.new(MCP::Protocol::Resource.new(name, uri, description, mime_type), handler)
      notify_resource_list_changed
    end

    def add_resources(resources : Array(RegisteredResource))
      if capabilities.resources.nil?
        Log.error { "Failed to add resources: Server does not support resources capability" }
        raise ArgumentError.new("Server does not support resources capability.")
      end

      Log.info { "Registering #{resources.size} resources" }
      resources.each do |rsc|
        Log.debug { "Registering resource: #{rsc.resource.name} #{rsc.resource.uri}" }
        @resources[rsc.resource.uri] = rsc
      end
      notify_resource_list_changed
    end

    def remove_resource(uri : String) : Bool
      if capabilities.resources.nil?
        Log.error { " Failed to remove resource #{uri}: Server does not support resources capability" }
        raise ArgumentError.new("Server does not support resources capability.")
      end
      Log.info { "Removing resource #{uri}" }
      _, removed = @resources.load_and_delete(uri)
      Log.debug {
        removed ? "Resource removed: #{uri}" : "Resource not found: #{uri}"
      }
      notify_resource_list_changed if removed
      removed
    end

    def remove_resources(uris : Array(String)) : Int32
      if capabilities.resources.nil?
        Log.error { " Failed to remove resources: Server does not support resources capability" }
        raise ArgumentError.new("Server does not support resources capability.")
      end

      res = uris.map { |uri| remove_resource(uri) }
      removed = res.count(&.== true)
      Log.info { removed > 0 ? "Removed #{removed} resources" : "No resources were removed" }
      notify_resource_list_changed if removed > 0
      removed
    end

    def ping : PingResult
      request(MCP::Protocol::PingRequest.new)
    end

    def create_message(params : MCP::Protocol::CreateMessageRequestParams, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::CreateMessageResult
      Log.debug { "Creating message with params: #{params.to_json}" }
      request(MCP::Protocol::CreateMessageRequest.new(params), options).as(MCP::Protocol::CreateMessageResult)
    end

    def list_roots(params : Hash(String, JSON::Any) = Hash(String, JSON::Any).new, options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::ListRootsResult
      Log.debug { "Listing roots with params: #{params}" }
      request(MCP::Protocol::ListRootsRequest.new(params), options).as(MCP::Protocol::ListRootsResult)
    end

    def create_elicitation(message : String, mode : String = "form",
                           requested_schema : Hash(String, JSON::Any)? = nil,
                           url : String? = nil, elicitation_id : String? = nil,
                           options : MCP::Shared::RequestOptions? = nil) : MCP::Protocol::ElicitResult
      Log.debug { "Creating elicitation: #{message}" }
      req = MCP::Protocol::CreateElicitationRequest.new(message, mode, requested_schema, url, elicitation_id)
      request(req, options).as(MCP::Protocol::ElicitResult)
    end

    def send_logging_message(params : MCP::Protocol::LoggingMessageNotificationParams)
      Log.trace { "Sending logging message: #{params.data}" }
      notification(MCP::Protocol::LoggingMessageNotification.new(params))
    end

    def send_resource_updated(params : MCP::Protocol::ResourceUpdatedNotificationParams)
      Log.debug { "Sending resource update notification for : #{params.uri}" }
      notification(MCP::Protocol::ResourceUpdatedNotification.new(params))
    end

    def send_resource_list_changed
      Log.debug { "Sending resource list changed notification" }
      notification(MCP::Protocol::ResourceListChangedNotification.new)
    end

    def send_tool_list_changed
      Log.debug { "Sending tool list changed notification" }
      notification(MCP::Protocol::ToolListChangedNotification.new)
    end

    def send_prompt_list_changed
      Log.debug { "Sending prompt list changed notification" }
      notification(MCP::Protocol::PromptListChangedNotification.new)
    end

    def subscribe_resource(uri : String) : Bool
      if capabilities.resources.nil?
        raise ArgumentError.new("Server does not support resources capability.")
      end
      @subscriptions.add(uri)
      true
    end

    def unsubscribe_resource(uri : String) : Bool
      if capabilities.resources.nil?
        raise ArgumentError.new("Server does not support resources capability.")
      end
      @subscriptions.delete(uri) != nil
    end

    def subscribed?(uri : String) : Bool
      @subscriptions.includes?(uri)
    end

    def tool_registered?(name : String) : Bool
      @tools.has_key?(name)
    end

    def resource_registered?(uri : String) : Bool
      @resources.has_key?(uri)
    end

    def add_resource_template(template : MCP::Protocol::ResourceTemplate, &handler : MCP::Protocol::ReadResourceRequestParams -> MCP::Protocol::ReadResourceResult)
      if capabilities.resources.nil?
        raise ArgumentError.new("Server does not support resources capability.")
      end
      Log.info { "Registering resource template #{template.name} #{template.uri_template}" }
      @resource_templates[template.uri_template] = RegisteredResourceTemplate.new(template, handler)
      notify_resource_list_changed
    end

    def resource_template_registered?(uri_template : String) : Bool
      @resource_templates.has_key?(uri_template)
    end

    def remove_resource_template(uri_template : String) : Bool
      if capabilities.resources.nil?
        raise ArgumentError.new("Server does not support resources capability.")
      end
      Log.info { "Removing resource template #{uri_template}" }
      _, removed = @resource_templates.load_and_delete(uri_template)
      notify_resource_list_changed if removed
      removed
    end

    def remove_resource_templates(uris : Array(String)) : Int32
      if capabilities.resources.nil?
        raise ArgumentError.new("Server does not support resources capability.")
      end
      res = uris.map { |uri| remove_resource_template(uri) }
      removed = res.count(&.== true)
      Log.info { removed > 0 ? "Removed #{removed} resource templates" : "No resource templates were removed" }
      notify_resource_list_changed if removed > 0
      removed
    end

    def clear_all
      had_tools = !@tools.empty?
      had_prompts = !@prompts.empty?
      had_resources = !@resources.empty? || !@resource_templates.empty?

      @tools.clear
      @prompts.clear
      @resources.clear
      @resource_templates.clear

      notify_tool_list_changed if had_tools
      notify_prompt_list_changed if had_prompts
      notify_resource_list_changed if had_resources
    end

    def prompt_registered?(name : String) : Bool
      @prompts.has_key?(name)
    end

    def set_completion_handler(&handler : MCP::Protocol::CompleteRequestParams -> MCP::Protocol::CompleteResult)
      @completion_handler = handler
    end

    private def notify_tool_list_changed
      return unless @transport
      return unless capabilities.tools.try(&.list_changed)
      send_tool_list_changed rescue nil
    end

    private def notify_prompt_list_changed
      return unless @transport
      return unless capabilities.prompts.try(&.list_changed)
      send_prompt_list_changed rescue nil
    end

    private def notify_resource_list_changed
      return unless @transport
      return unless capabilities.resources.try(&.list_changed)
      send_resource_list_changed rescue nil
    end

    def on_logging_level_change(&callback : MCP::Protocol::LoggingLevel ->)
      @_on_logging_level_change = callback
    end

    private def handle_set_level(request : MCP::Protocol::SetLevelRequestParams) : MCP::Protocol::EmptyResult
      Log.debug { "Handling set level request: #{request.level}" }
      @logging_level = request.level
      @_on_logging_level_change.try &.call(request.level)
      MCP::Protocol::EmptyResult.new
    end

    private def handle_complete(request : MCP::Protocol::CompleteRequestParams) : MCP::Protocol::CompleteResult
      Log.debug { "Handling completion request for: #{request.to_json}" }
      if handler = @completion_handler
        handler.call(request)
      else
        MCP::Protocol::CompleteResult.new(MCP::Protocol::CompleteResult::Completion.new)
      end
    end

    private def handle_subscribe_resource(request : MCP::Protocol::SubscribeRequestParams) : MCP::Protocol::EmptyResult
      Log.debug { "Handling subscribe resource request for: #{request.uri}" }
      @subscriptions.add(request.uri)
      MCP::Protocol::EmptyResult.new
    end

    private def handle_unsubscribe_resource(request : MCP::Protocol::UnsubscribeRequestParams) : MCP::Protocol::EmptyResult
      Log.debug { "Handling unsubscribe resource request for: #{request.uri}" }
      @subscriptions.delete(request.uri)
      MCP::Protocol::EmptyResult.new
    end

    private def handle_initialize(request : MCP::Protocol::InitializeRequestParams) : MCP::Protocol::InitializeResult
      Log.info { "Handling initialize request from client #{request.client_info.to_json}" }
      @client_capabilities = request.capabilities
      @client_version = request.client_info

      requested_version = request.protocol_version
      protocol_version = Protocol::SUPPORTED_PROTOCOL_VERSIONS.includes?(requested_version) ? requested_version : begin
        Log.warn { "Client requested unsupported protocol version #{requested_version}, falling back to #{Protocol::LATEST_PROTOCOL_VERSION}" }
        Protocol::LATEST_PROTOCOL_VERSION
      end

      MCP::Protocol::InitializeResult.new(
        protocol_version: protocol_version,
        capabilities: capabilities,
        server_info: server_info
      )
    end

    private def handle_list_tools : MCP::Protocol::ListToolsResult
      items = @tools.keys.sort!
      result = paginate(items, nil)
      MCP::Protocol::ListToolsResult.new(
        tools: result[:items].map { |name| @tools[name].tool },
        next_cursor: result[:next_cursor]
      )
    end

    private def paginate(keys : Array(String), cursor : String?)
      limit = server_options.pagination_limit
      return {items: keys, next_cursor: nil} unless limit

      start_idx = 0
      if cursor
        decoded = Base64.decode_string(cursor)
        start_idx = keys.index!(decoded) + 1
      end

      slice = keys[start_idx, limit]?
      return {items: keys, next_cursor: nil} unless slice

      next_cursor = nil
      if start_idx + limit < keys.size
        last_key = slice.last
        next_cursor = Base64.strict_encode(last_key)
      end

      {items: slice, next_cursor: next_cursor}
    end

    private def handle_call_tool(request : MCP::Protocol::CallToolRequestParams) : MCP::Protocol::CallToolResult
      Log.debug { "Handling tool call request for tool: #{request.name}" }
      tool = @tools[request.name]? || raise "Tool not found: #{request.name}"
      Log.trace { "Executing tool #{request.name} with input: #{request.arguments.to_json}" }
      tool.handler.call(request)
    end

    private def handle_list_prompts : MCP::Protocol::ListPromptsResult
      Log.debug { "Handling list prompts request" }
      MCP::Protocol::ListPromptsResult.new(prompts: @prompts.values.map(&.prompt))
    end

    private def handle_get_prompt(request : MCP::Protocol::GetPromptRequestParams) : MCP::Protocol::GetPromptResult
      Log.debug { "Handling get prompt request for: #{request.name}" }
      prompt = @prompts[request.name]? || raise "Prompt not found: #{request.name}"
      prompt.handler.call(request)
    end

    private def handle_list_resources : MCP::Protocol::ListResourcesResult
      Log.debug { "Handling list resources request" }
      MCP::Protocol::ListResourcesResult.new(resources: @resources.values.map(&.resource))
    end

    private def handle_read_resource(request : MCP::Protocol::ReadResourceRequestParams) : MCP::Protocol::ReadResourceResult
      Log.info { "Handling read resource request for: #{request.uri}" }
      resource = @resources[request.uri]? || match_resource_template(request.uri)
      raise "Resource not found: #{request.uri}" unless resource
      resource.handler.call(request)
    end

    private def match_resource_template(uri : String) : RegisteredResourceTemplate?
      @resource_templates.each do |url_template, registered|
        regex_str = "^" + url_template.gsub(/\{[^}]*\*[^}]*\}/, "(.+)")
        regex_str = regex_str.gsub(/\{[^}]+\}/, "([^/]+)") + "$"
        if uri =~ Regex.new(regex_str)
          return registered
        end
      end
      nil
    end

    private def handle_list_resource_templates : MCP::Protocol::ListResourceTemplatesResult
      MCP::Protocol::ListResourceTemplatesResult.new(
        resource_templates: @resource_templates.values.map(&.template)
      )
    end

    # Capability validation
    def assert_capability_for_method(method : String)
      Log.trace { "Asserting capability for method: #{method}" }
      case method
      when "sampling/createMessage"
        unless client_capabilities.try(&.sampling)
          Log.error { "Client capability assertion failed: sampling not supported" }
          raise "Client does not support sampling (required for #{method})"
        end
      when "roots/list"
        unless client_capabilities.try(&.roots)
          raise "Client does not support listing roots (required for #{method})"
        end
      when "ping"
        # No specific capability required
      end
    end

    def assert_notification_capability(method : String)
      Log.debug { "Asserting notification capability for method: #{method}" }
      case method
      when "notifications/message"
        if capabilities.logging.nil?
          Log.error { "Server capability assertion failed: logging not supported" }
          raise "Server does not support logging (required for #{method})"
        end
      when "notifications/resources/updated"
        if capabilities.resources.nil?
          raise "Server does not support notifying about resources (required for #{method})"
        end
        if capabilities.resources.try(&.subscribe).nil?
          raise "Server does not support resource subscriptions (required for #{method})"
        end
      when "notifications/resources/list_changed"
        raise "Server does not support notifying about resources (required for method #{method})" unless capabilities.resources
      when "notifications/tools/list_changed"
        raise "Server does not support notifying of tool list changes (required for #{method})" unless capabilities.tools
      when "notifications/prompts/list_changed"
        raise "Server does not support notifying of prompt list changes (required for #{method})" unless capabilities.prompts
      when "notifications/cancelled", "notifications/progress"
        # always allowed
      end
    end

    def assert_request_handler_capability(method : String)
      Log.trace { "Asserting request handler capability for method: #{method}" }

      case method
      when "sampling/createMessage"
        if capabilities.sampling.nil?
          Log.error { "Server capability assertion failed: sampling not supported" }
          raise "Server does not support sampling (required for #{method})"
        end
      when "logging/setLevel"
        if capabilities.logging.nil?
          raise "Server does not support logging (required for #{method})"
        end
      when "prompts/get", "prompts/list"
        if capabilities.prompts.nil?
          raise "Server does not support prompts (required for #{method})"
        end
      when "resources/list", "resources/templates/list", "resources/read", "resources/subscribe", "resources/unsubscribe"
        if capabilities.resources.nil?
          raise "Server does not support resources (required for #{method})"
        end
      when "completion/complete"
        if capabilities.completions.nil?
          raise "Server does not support completions (required for #{method})"
        end
      when "tools/call", "tools/list"
        if capabilities.tools.nil?
          raise "Server does not support tools (required for #{method})"
        end
      when "ping", "initialize"
        # No capability required
      end
    end

    record RegisteredTool, tool : MCP::Protocol::Tool, handler : (MCP::Protocol::CallToolRequestParams) -> MCP::Protocol::CallToolResult
    record RegisteredPrompt, prompt : MCP::Protocol::Prompt, handler : (MCP::Protocol::GetPromptRequestParams) -> MCP::Protocol::GetPromptResult
    record RegisteredResource, resource : MCP::Protocol::Resource, handler : (MCP::Protocol::ReadResourceRequestParams) -> MCP::Protocol::ReadResourceResult
    record RegisteredResourceTemplate, template : MCP::Protocol::ResourceTemplate, handler : (MCP::Protocol::ReadResourceRequestParams) -> MCP::Protocol::ReadResourceResult
  end
end
