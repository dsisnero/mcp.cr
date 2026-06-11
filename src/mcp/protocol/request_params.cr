require "./reference"

module MCP::Protocol
  abstract class RequestParams
    include JSON::Serializable

    @[JSON::Field(key: "_meta")]
    property meta : Hash(String, JSON::Any)?

    def initialize(@meta = nil)
    end

    def progress_token : ProgressToken?
      meta["progressToken"]?
    end

    def progress_token=(value : ProgressToken?)
      return meta.delete("progressToken") if value.nil?
      meta["progressToken"] = JSON::Any.new(value)
    end
  end

  abstract class PaginateRequestdParams < RequestParams
    getter cursor : Cursor?

    def initialize(@cursor = nil, meta = nil)
      super(meta)
    end
  end

  class CallToolRequestParams < RequestParams
    getter name : String
    getter arguments : Hash(String, JSON::Any)?

    def initialize(@name, @arguments = nil, @meta = nil)
      super(@meta)
    end
  end

  struct CompleteContext
    include JSON::Serializable
    getter arguments : Hash(String, String)

    def initialize(@arguments)
    end
  end

  class CompleteRequestParams < RequestParams
    getter ref : MCPReference
    getter argument : Argument
    getter context : CompleteContext?

    def initialize(@ref, @argument, @context, @meta = nil)
      super(@meta)
    end
  end

  struct SamplingMessage
    include JSON::Serializable

    getter role : Role
    getter content : ContentBlock

    def initialize(@role, @content)
    end
  end

  struct ModelHint
    include JSON::Serializable
    getter name : String?

    def initialize(@name = nil)
    end
  end

  struct ModelPreferences
    include JSON::Serializable

    @[JSON::Field(key: "costPriority")]
    getter cost_priority : Float64?

    getter hints : Array(ModelHint)?

    @[JSON::Field(key: "speedPriority")]
    getter speed_priority : Float64?

    @[JSON::Field(key: "intelligencePriority")]
    getter intelligence_priority : Float64?

    def initialize(@hints = nil, @cost_priority = nil, @speed_priority = nil, @intelligence_priority = nil)
    end
  end

  class CreateMessageRequestParams < RequestParams
    @[JSON::Field(key: "includeContext")]
    getter include_context : ContextInclusion?

    @[JSON::Field(key: "maxTokens")]
    getter max_tokens : Int32

    getter messages : Array(SamplingMessage)
    getter metadata : JSON::Any?

    @[JSON::Field(key: "modelPreferences")]
    getter model_preferences : ModelPreferences?

    @[JSON::Field(key: "stopSequences")]
    getter stop_sequences : Array(String)?

    @[JSON::Field(key: "systemPrompt")]
    getter system_prompt : String?

    getter temperature : Float64?

    def initialize(@messages, @max_tokens, @system_prompt = nil, @include_context = nil,
                   @temperature = nil, @stop_sequences = nil, @metadata = nil,
                   @model_preferences = nil, @meta = nil)
      super(@meta)
    end
  end

  class CreateElicitationRequestParams < RequestParams
    getter mode : String
    getter message : String
    @[JSON::Field(key: "requestedSchema")]
    getter requested_schema : Hash(String, JSON::Any)?
    getter url : String?
    @[JSON::Field(key: "elicitationId")]
    getter elicitation_id : String?

    def initialize(@message, @mode = "form", @requested_schema = nil,
                   @url = nil, @elicitation_id = nil, @meta = nil)
      super(@meta)
    end

    def self.form(message : String, schema : Hash(String, JSON::Any)) : self
      new(message: message, mode: "form", requested_schema: schema)
    end

    def self.url(message : String, url : String, elicitation_id : String) : self
      new(message: message, mode: "url", url: url, elicitation_id: elicitation_id)
    end
  end

  class GetPromptRequestParams < RequestParams
    getter name : String
    getter arguments : Hash(String, JSON::Any)?

    def initialize(@name, @arguments = nil, @meta = nil)
      super(@meta)
    end
  end

  struct RootsCapability
    include JSON::Serializable

    @[JSON::Field(key: "listChanged")]
    getter list_changed : Bool?

    def initialize(@list_changed = nil)
    end
  end

  class ClientCapabilities
    include JSON::Serializable

    property experimental : Hash(String, JSON::Any)?
    property roots : RootsCapability?
    property sampling : Hash(String, JSON::Any)?
    property elicitation : Hash(String, JSON::Any)?
    property tasks : Hash(String, JSON::Any)?
    property extensions : Hash(String, JSON::Any)?

    def initialize(@experimental = nil, @sampling = nil, @elicitation = nil, @roots = nil, @tasks = nil, @extensions = nil)
    end

    def self.with_roots(list_changed : Bool? = nil)
      new(roots: RootsCapability.new(list_changed))
    end
  end

  struct Implementation
    include JSON::Serializable

    getter name : String
    getter title : String?
    getter version : String
    getter icons : Array(Icon)?

    def initialize(@name, @version, @title = nil, @icons = nil)
    end
  end

  class InitializeRequestParams < RequestParams
    @[JSON::Field(key: "protocolVersion")]
    getter protocol_version : String
    getter capabilities : ClientCapabilities
    @[JSON::Field(key: "clientInfo")]
    getter client_info : Implementation

    def initialize(@protocol_version, @capabilities, @client_info, @meta = nil)
      super(@meta)
    end
  end

  class ListPromptsRequestParams < PaginateRequestdParams
    def initialize(@cursor = nil, meta = nil)
      super
    end
  end

  class ListResourcesRequestParams < PaginateRequestdParams
    def initialize(@cursor = nil, meta = nil)
      super
    end
  end

  class ListResourceTemplatesRequestParams < PaginateRequestdParams
    def initialize(@cursor = nil, meta = nil)
      super
    end
  end

  class ListRootsRequestParams < RequestParams
    def initialize(@meta = nil)
      super
    end
  end

  class ListToolsRequestParams < PaginateRequestdParams
    def initialize(@cursor = nil, meta = nil)
      super
    end
  end

  class ReadResourceRequestParams < RequestParams
    getter uri : String

    def initialize(@uri, @meta = nil)
      super(@meta)
    end
  end

  enum LoggingLevel
    Debug
    Info
    Notice
    Warning
    Error
    Critical
    Alert
    Emergency
  end

  class SetLevelRequestParams < RequestParams
    getter level : LoggingLevel

    def initialize(@level, @meta = nil)
      super(@meta)
    end
  end

  class SubscribeRequestParams < RequestParams
    getter uri : String

    def initialize(@uri, @meta = nil)
      super(@meta)
    end
  end

  class UnsubscribeRequestParams < RequestParams
    getter uri : String

    def initialize(@uri, @meta = nil)
      super(@meta)
    end
  end

  class PingRequestParams < RequestParams
    def initialize(@meta = nil)
      super(@meta)
    end
  end
end
