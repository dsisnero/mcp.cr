# Crystal MCP: Unofficial Crystal Implementation of the Model Context Protocol

This is an unofficial Crystal language implementation of the [Model Context Protocol (MCP)](https://modelcontextprotocol.io), offering both client and server functionality to enable seamless integration with LLM interfaces across a variety of platforms.

## Overview

The Model Context Protocol (MCP) standardizes how applications provide contextual information to large language models (LLMs), decoupling context management from the LLM runtime itself.

This Crystal shard brings full MCP compatibility to your applications, allowing you to:

* Develop MCP clients that can connect to any MCP-compliant server
* Implement MCP servers that expose **resources**, **prompts**, and **tools**
* Use standard transports such as **STDIO**, **SSE**, **HTTP Streamable**
* Manage the full MCP message flow and lifecycle events effortlessly


### TODO

Implement

- [X] SSE Transport
- [X] Streamable HTTP Transport
- [ ] WebSocket transports (optional)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     mcp:
       github: spider-gazelle/mcp.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "mcp"
```
### Quick Start

### Creating a Server

#### Easy way (Annotate and enjoy)

```crystal
require "mcp"

@[MCP::MCPServer(name: "weather_service", version: "2.1.0", tools: false, prompts: false, resources: false)]
@[MCP::Transport(type: streamable, endpoint: "/mymcp")]
class WeatherMCPServer
  include MCP::Annotator

  getter(weather_client : WeatherApi) { WeatherApi.new }

  @[MCP::Tool(
    name: "weather_alerts",
    description: "Get weather alerts for a US state. Input is Two-letter US state code (e.g. CA, NY)"
  )]
  def get_alerts(@[MCP::Param(description: "Two-letter US state code (e.g. CA, NY)")] state : String,
                 @[MCP::Param(description: "size of result")] limit : Int32?) : Array(String)
    weather_client.get_alerts(state)
  end

  @[MCP::Tool(description: "Get weather forecast for a specific latitude/longitude")]
  def get_forecast(@[MCP::Param(description: "Latitude coordinate", minimum: -90, maximum: 90)] latitude : Float64,
                   @[MCP::Param(description: "Longitude coordinate", minimum: -180, maximum: 107)] longitude : Float64) : Array(String)
    weather_client.get_forecast(latitude, longitude)
  end

  @[MCP::Prompt(
    name: "simple",
    description: "A simple prompt that can take optional context and topic"
  )]
  def simple_prompt(@[MCP::Param(description: "Additional context to consider")] context : String?,
                    @[MCP::Param(description: "A Specific topic to focus on")] topic : String?) : String
    String.build do |str|
      str << "Here is some relevant context: #{context}" if context
      str << "Please help with "
      str << (topic ? "the following topic: #{topic}" : "whatever questions I may have")
    end
  end

  @[MCP::Resource(name: "greeting", uri: "file:///greeting.txt", description: "Sample text resource", mime_type: "text/plain")]
  def read_text_resource(uri : String) : String
    raise "Invalid resource uri '#{uri}' or resource does not exist" unless uri == "file:///greeting.txt"
    "Hello! This is a sample text resource."
  end
end

WeatherMCPServer.run
```

#### Why the Unusual Name `MCP::MCPServer`?

The annotation is named `MCPServer` instead of the more intuitive `Server` to avoid a naming conflict with the existing `MCP::Server` module.

#### `MCP::MCPServer` Annotation

The `MCP::MCPServer` annotation is used to configure an MCP Server instance. Here's how its fields work:

* **`name` and `version`**: These populate the `serverInfo` field during the `initialize` lifecycle event.
* **`tools`, `prompts`, `resources`** *(optional)*: These flags indicate if your server supports updates or notifications for these elements.

If you set any of `tools`, `prompts`, or `resources` to `true`, you're responsible for notifying the MCP client when those lists change. For example:

If `resources: true` is set, and the resource list changes, you must call:

```crystal
server.send_resource_list_changed
```

This informs the client that the resource list has been updated.

#### `MCP::Transport` Annotation

This annotation defines the supported transport types for the MCP Server. It supports three modes:

* `stdio`: Standard input/output
* `sse`: Server-Sent Events
* `streamable`: Streamable HTTP


#### Hard way (Low-level API calls)
```crystal
require "mcp"

    server = MCP::Server::Server.new(
      MCP::Protocol::Implementation.new(name: "test server", version: "1.0"),
      MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(
        MCP::Server::ServerCapabilities.new
        .with_tools
        .with_resources))
    )

    server.add_tool("test-tool", "Test Tool", MCP::Protocol::Tool::Input.new) { |_request|
      contents = [] of MCP::Protocol::ContentBlock
      contents << MCP::Protocol::TextContentBlock.new("Test result")
      MCP::Protocol::CallToolResult.new(contents)
    }

    transport = MCP::Server::StdioServerTransport(...)
    server.connect(transport)
```

#### Auto-generating tool input schemas

Instead of manually constructing a `Tool::Input`, pass a typed handler `Proc(T -> CallToolResult)`
where `T` includes `JSON::Serializable`. The input schema is auto-generated from `T` via
the `json-schema` shard, and the handler receives a fully-deserialized typed input:

```crystal
struct MyToolInput
  include JSON::Serializable
  property name : String
  property age : Int32?
end

server.add_tool("my-tool", "Processes user input",
  ->(input : MyToolInput) : MCP::Protocol::CallToolResult {
    MCP::Protocol::CallToolResult.new([
      MCP::Protocol::TextContentBlock.new("Hello #{input.name}")
    ])
  }
)
```

#### ToolRouter for dynamic enable/disable

`Server#tool_router` exposes a `ToolRouter` view over registered tools,
supporting enable/disable and name-based dispatch. `Server#prompt_router`
and `Server#resource_router` work the same way:

```crystal
server.add_tool("greet", "Greets", MCP::Protocol::Tool::Input.new) { |_| ... }

server.tool_router.has_tool?("greet")  # => true
server.tool_router.disable("greet")
server.tool_router.enable("greet")
```

#### Async tool handlers

Register a tool handler that performs async work (e.g. an HTTP call) without
blocking the server's request-processing fiber. The handler receives both the
request params and a `RequestHandlerExtra` for cancellation checking, returning
a `Channel(AsyncResult(CallToolResult))`:

```crystal
server.add_tool_async("lookup", "Async name lookup", MCP::Protocol::Tool::Input.new) do |params, extra|
  channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)

  spawn do
    # do async work: call an API, query a DB, etc.
    sleep 100.milliseconds
    result = MCP::Protocol::CallToolResult.new([
      MCP::Protocol::TextContentBlock.new("Found #{params.name}")
    ])
    channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(value: result))
    channel.close
  end

  channel
end

result = client.call_tool("lookup", {"name" => JSON::Any.new("Alice")})
```

The `ToolRouter` also supports async handlers with the same enable/disable/remove
semantics:

```crystal
router = MCP::Server::ToolRouter.new
router.add_tool_async("async_greet") do |params, extra|
  channel = Channel(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult)).new(1)
  spawn do
    channel.send(MCP::Shared::AsyncResult(MCP::Protocol::CallToolResult).new(
      value: MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("hi")] of MCP::Protocol::ContentBlock)
    ))
    channel.close
  end
  channel
end

router.call("async_greet", params)
```

### Creating a Client

`Client` is safe for concurrent use by multiple fibers.  `call_tool`, `request`,
`call_tool_async`, and all other public methods may be called from many fibers
on a single client with no external serialization — every reply is correctly
matched to its caller.

```crystal
require "mcp"

  client = MCP::Client::Client.new(
    client_info: MCP::Protocol::Implementation.new("test client", "1.0"),
    client_options: MCP::Client::ClientOptions.new(
      capabilities: MCP::Protocol::ClientCapabilities.new))

    process = Process.new(
      "path-to-some-mcp-server .....",
      input: :pipe,
      output: :pipe
    )

    transport = MCP::Client::StdioClientTransport.new(
      input: process.input,
      output: process.output
    )

    # Connect to Server
    client.connect(transport)

    # List available resources
    resources = client.list_resources

    # Read a specific resource
    resource = MCP::Protocol::ReadResourceRequest.new(uri: "file:///example.txt")
    content = client.read_resource(resource)
```

#### Overlapping tool calls (async)

A single client can issue overlapping, non-blocking tool calls with `call_tool_async`.
It returns a `Channel` that yields an `MCP::Shared::AsyncResult`; call `#unwrap` to get
the result (it re-raises any handler error):

```crystal
first  = client.call_tool_async("slow-tool", {} of String => JSON::Any)
second = client.call_tool_async("slow-tool", {} of String => JSON::Any)

result_a = first.receive.unwrap
result_b = second.receive.unwrap
```

#### SSE client transport

Connect to an MCP server over Server-Sent Events with automatic reconnect:

```crystal
transport = MCP::Client::SseClientTransport.new("http://host:port/sse")
transport.on_message { |msg| ... }
transport.start

# The transport auto-extracts the POST endpoint from the SSE
# 'event: endpoint' control frame; send() posts to it.
transport.send(MCP::Protocol::PingRequest.new)
transport.close
```

#### Elicitation schema builder

Build MCP 2025-06-18 compliant elicitation schemas with a fluent, type-safe API:

```crystal
schema = MCP::Protocol::ElicitationSchema.builder
  .required_email("email")
  .required_integer("age", 0_i64, 150_i64)
  .optional_bool("newsletter", false)
  .title("User Registration")
  .build

schema.to_json # => {"type":"object","properties":{...},"required":["email","age"]}
```

Refer to [samples](samples) folder for samples

## Development

To run all tests:

```
crystal spec
```

## Contributing

1. Fork it (<https://github.com/spider-gazelle/mcp.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Ali Naqvi](https://github.com/naqvis) - creator and maintainer
