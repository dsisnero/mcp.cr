require "../spec_helper"

describe MCP::Server::Server do
  it "remove_tool should remove a tool" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("test-tool", "Test Tool", MCP::Protocol::Tool::Input.new) { |_request|
      contents = [] of MCP::Protocol::ContentBlock
      contents << MCP::Protocol::TextContentBlock.new("Test result")
      MCP::Protocol::CallToolResult.new(contents)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_tool("test-tool")
    result.should be_true
  end

  it "remove_tool should return false when tool does not exists" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    list_changed_notification = false

    client.notification_handler(MCP::Protocol::NotificationsToolsListChanged) {
      list_changed_notification = true
      nil
    }

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_tool("non-existent-tool")
    result.should be_false
    list_changed_notification.should be_false
  end

  it "remove_tool should raise when tools capabaility is not supported" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    expect_raises(Exception, "Server does not support tools capability") do
      server.remove_tool("non-existent-tool")
    end
  end

  it "remove_prompt should remove a prompt" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(prompts: MCP::Server::ServerCapabilities.new.with_prompts.prompts))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    prompt = MCP::Protocol::Prompt.new("test-prompt", " Test Prompt")
    server.add_prompt(prompt) { |_request|
      MCP::Protocol::GetPromptResult.new(description: "Test Prompt description", messages: [] of MCP::Protocol::PromptMessage)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_prompt(prompt.name)
    result.should be_true
  end

  it "remove_prompt should remove multiple prompts and send notification" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(prompts: MCP::Server::ServerCapabilities.new.with_prompts.prompts))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    prompt1 = MCP::Protocol::Prompt.new("test-prompt-1", " Test Prompt 1")
    prompt2 = MCP::Protocol::Prompt.new("test-prompt-2", " Test Prompt 2")

    server.add_prompt(prompt1) { |_request|
      MCP::Protocol::GetPromptResult.new(description: "Test Prompt description 1", messages: [] of MCP::Protocol::PromptMessage)
    }

    server.add_prompt(prompt2) { |_request|
      MCP::Protocol::GetPromptResult.new(description: "Test Prompt description 2", messages: [] of MCP::Protocol::PromptMessage)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_prompts([prompt1.name, prompt2.name])
    result.should eq(2)
  end

  it "remove_resource should remove a resource and send notification" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(resources: MCP::Server::ServerCapabilities.new.with_resources.resources))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    test_resource_uri = "test://resource"
    server.add_resource(uri: test_resource_uri, name: "Test Resource", description: "A test resource", mime_type: "text/plain") { |_request|
      MCP::Protocol::ReadResourceResult.new(contents: [MCP::Protocol::TextResourceContents.new(text: "Test resource content", uri: test_resource_uri, mime_type: "text/plain")] of MCP::Protocol::ResourceContents)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_resource(test_resource_uri)
    result.should be_true
  end

  it "remove_resource should remove multiple resources and send notification" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(resources: MCP::Server::ServerCapabilities.new.with_resources.resources))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    test_resource_uri1 = "test://resource1"
    test_resource_uri2 = "test://resource2"

    server.add_resource(uri: test_resource_uri1, name: "Test Resource 1", description: "A test resource 1", mime_type: "text/plain") { |_request|
      MCP::Protocol::ReadResourceResult.new(contents: [MCP::Protocol::TextResourceContents.new(text: "Test resource content 1", uri: test_resource_uri1, mime_type: "text/plain")] of MCP::Protocol::ResourceContents)
    }

    server.add_resource(uri: test_resource_uri2, name: "Test Resource 2", description: "A test resource 2", mime_type: "text/plain") { |_request|
      MCP::Protocol::ReadResourceResult.new(contents: [MCP::Protocol::TextResourceContents.new(text: "Test resource content 2", uri: test_resource_uri2, mime_type: "text/plain")] of MCP::Protocol::ResourceContents)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_resources([test_resource_uri1, test_resource_uri2])
    result.should eq(2)
  end

  it "remove_prompt should raise when prompts capability is not supported" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    expect_raises(Exception, "Server does not support prompts capability") do
      server.remove_prompt("test-prompt")
    end
  end

  it "add_tools should register multiple tools" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    tool1 = MCP::Protocol::Tool.new("test-tool-1", MCP::Protocol::Tool::Input.new, "Test Tool 1")
    tool2 = MCP::Protocol::Tool.new("test-tool-2", MCP::Protocol::Tool::Input.new, "Test Tool 2")

    handler = ->(_request : MCP::Protocol::CallToolRequestParams) : MCP::Protocol::CallToolResult {
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("result")] of MCP::Protocol::ContentBlock)
    }

    registered_tools = [
      MCP::Server::Server::RegisteredTool.new(tool1, handler),
      MCP::Server::Server::RegisteredTool.new(tool2, handler),
    ]

    server.add_tools(registered_tools)

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_tool("test-tool-1")
    result.should be_true
  end

  it "subscribe_resource should add a subscription" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(resources: MCP::Server::ServerCapabilities.new.with_resources(subscribe: true).resources))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    result = server.subscribe_resource("test://sub")
    result.should be_true
    server.subscribed?("test://sub").should be_true
  end

  it "unsubscribe_resource should remove a subscription" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(resources: MCP::Server::ServerCapabilities.new.with_resources(subscribe: true).resources))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.subscribe_resource("test://sub")
    server.subscribed?("test://sub").should be_true

    result = server.unsubscribe_resource("test://sub")
    result.should be_true
    server.subscribed?("test://sub").should be_false
  end

  it "subscribe_resource should raise when resources capability is not supported" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    expect_raises(Exception, "Server does not support resources capability") do
      server.subscribe_resource("test://sub")
    end
  end

  it "complete should return empty completions by default" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(completions: {} of String => JSON::Any))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    received = Channel(MCP::Protocol::JSONRPCMessage).new(1)
    client_transport.on_message { |msg| received.send(msg) }

    spawn { server.connect(server_transport) }
    Fiber.yield

    request = MCP::Protocol::CompleteRequest.new(
      ref: MCP::Protocol::PromptReference.new(name: "test"),
      arg_name: "arg",
      arg_value: ""
    )
    client_transport.send(request)

    resp = received.receive
    resp.should be_a(MCP::Protocol::JSONRPCResponse)
    result = resp.as(MCP::Protocol::JSONRPCResponse).result
    result.should be_a(MCP::Protocol::CompleteResult)
  end

  it "set_level should accept logging level change" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(logging: {} of String => JSON::Any))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    received = Channel(MCP::Protocol::JSONRPCMessage).new(1)
    client_transport.on_message { |msg| received.send(msg) }

    spawn { server.connect(server_transport) }
    Fiber.yield

    request = MCP::Protocol::SetLevelRequest.new(level: MCP::Protocol::LoggingLevel::Debug)
    client_transport.send(request)

    resp = received.receive
    resp.should be_a(MCP::Protocol::JSONRPCResponse)
    resp.as(MCP::Protocol::JSONRPCResponse).result.should be_a(MCP::Protocol::EmptyResult)
  end

  it "add_resources should register multiple resources" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(resources: MCP::Server::ServerCapabilities.new.with_resources.resources))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    uri1 = "test://resource1"
    uri2 = "test://resource2"

    handler = ->(request : MCP::Protocol::ReadResourceRequestParams) : MCP::Protocol::ReadResourceResult {
      MCP::Protocol::ReadResourceResult.new(
        contents: [MCP::Protocol::TextResourceContents.new(text: "content", uri: request.uri, mime_type: "text/plain")] of MCP::Protocol::ResourceContents
      )
    }

    registered_resources = [
      MCP::Server::Server::RegisteredResource.new(
        MCP::Protocol::Resource.new("Resource1", uri1, "desc1", "text/plain"),
        handler
      ),
      MCP::Server::Server::RegisteredResource.new(
        MCP::Protocol::Resource.new("Resource2", uri2, "desc2", "text/plain"),
        handler
      ),
    ]

    server.add_resources(registered_resources)

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }

    result = server.remove_resource(uri1)
    result.should be_true
  end

  it "add_tool should auto-send list_changed notification when connected" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools(list_changed: true).tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    notification_received = false
    client.notification_handler(MCP::Protocol::NotificationsToolsListChanged) {
      notification_received = true
      nil
    }

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }
    Fiber.yield
    Fiber.yield

    server.add_tool("auto-notify-tool", "Test", MCP::Protocol::Tool::Input.new) { |_|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    }

    notification_received.should be_true
  end

  it "remove_tool should auto-send list_changed notification when connected" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools(list_changed: true).tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("auto-notify-tool", "Test", MCP::Protocol::Tool::Input.new) { |_|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    client = MCP::Client::Client.new(client_info: MCP::Protocol::Implementation.new("test-client", "1.0"))

    notification_received = false
    client.notification_handler(MCP::Protocol::NotificationsToolsListChanged) {
      notification_received = true
      nil
    }

    spawn { client.connect(client_transport) }
    spawn { server.connect(server_transport) }
    Fiber.yield
    Fiber.yield

    server.remove_tool("auto-notify-tool")

    notification_received.should be_true
  end

  it "tool_registered? should return true for registered tool" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("existing-tool", "Test", MCP::Protocol::Tool::Input.new) { |_|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    }

    server.tool_registered?("existing-tool").should be_true
    server.tool_registered?("nonexistent").should be_false
  end

  it "resource_registered? should return true for registered resource" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(resources: MCP::Server::ServerCapabilities.new.with_resources.resources))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_resource(uri: "test://res", name: "R", description: "d", mime_type: "text/plain") { |_|
      MCP::Protocol::ReadResourceResult.new(contents: [] of MCP::Protocol::ResourceContents)
    }

    server.resource_registered?("test://res").should be_true
    server.resource_registered?("test://nonexistent").should be_false
  end

  it "prompt_registered? should return true for registered prompt" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(prompts: MCP::Server::ServerCapabilities.new.with_prompts.prompts))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    prompt = MCP::Protocol::Prompt.new("existing-prompt", "Test")
    server.add_prompt(prompt) { |_| MCP::Protocol::GetPromptResult.new([] of MCP::Protocol::PromptMessage) }

    server.prompt_registered?("existing-prompt").should be_true
    server.prompt_registered?("nonexistent").should be_false
  end

  it "content constructors should create content blocks" do
    text = MCP.text_content("hello world")
    text.should be_a(MCP::Protocol::TextContentBlock)
    text.text.should eq("hello world")

    image = MCP.image_content("base64data", "image/png")
    image.should be_a(MCP::Protocol::ImageContentBlock)
    image.mime_type.should eq("image/png")

    result = MCP.tool_result("result text")
    result.should be_a(MCP::Protocol::CallToolResult)
    result.content.first.should be_a(MCP::Protocol::TextContentBlock)
  end

  it "list_tools should support cursor-based pagination" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools), pagination_limit: 2)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    5.times do |i|
      server.add_tool("tool-#{i}", "Tool #{i}", MCP::Protocol::Tool::Input.new) { |_|
        MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("result")] of MCP::Protocol::ContentBlock)
      }
    end

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    received = Channel(MCP::Protocol::JSONRPCMessage).new(2)
    client_transport.on_message { |msg| received.send(msg) }

    spawn { server.connect(server_transport) }
    Fiber.yield

    # First page
    request = MCP::Protocol::ListToolsRequest.new
    client_transport.send(request)
    resp = received.receive
    resp.should be_a(MCP::Protocol::JSONRPCResponse)
    result = resp.as(MCP::Protocol::JSONRPCResponse).result.as(MCP::Protocol::ListToolsResult)
    result.tools.size.should eq(2)
    result.next_cursor.should_not be_nil
  end

  it "should register and list resource templates" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(resources: MCP::Server::ServerCapabilities.new.with_resources.resources))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    template = MCP::Protocol::ResourceTemplate.new("MyTemplate", "file:///{path}", "A template")
    server.add_resource_template(template) { |_|
      MCP::Protocol::ReadResourceResult.new(contents: [] of MCP::Protocol::ResourceContents)
    }

    server.resource_template_registered?("file:///{path}").should be_true

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    received = Channel(MCP::Protocol::JSONRPCMessage).new(2)
    client_transport.on_message { |msg| received.send(msg) }

    spawn { server.connect(server_transport) }
    Fiber.yield

    request = MCP::Protocol::ListResourceTemplatesRequest.new
    client_transport.send(request)

    resp = received.receive
    resp.should be_a(MCP::Protocol::JSONRPCResponse)
    result = resp.as(MCP::Protocol::JSONRPCResponse).result.as(MCP::Protocol::ListResourceTemplatesResult)
    result.resource_templates.size.should eq(1)
    result.resource_templates.first.name.should eq("MyTemplate")
  end

  it "should allow request handlers to run in separate fibers" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    handler_fiber = Channel(Fiber).new(1)

    server.add_tool("fiber-check", "Checks fiber", MCP::Protocol::Tool::Input.new) { |_|
      handler_fiber.send(Fiber.current)
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    }

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    response = Channel(MCP::Protocol::JSONRPCMessage).new(1)
    client_transport.on_message { |msg| response.send(msg) }

    spawn { server.connect(server_transport) }
    Fiber.yield

    test_fiber = Fiber.current
    client_transport.send(MCP::Protocol::CallToolRequest.new(name: "fiber-check"))

    handler_f = handler_fiber.receive
    resp = response.receive
    resp.should be_a(MCP::Protocol::JSONRPCResponse)

    # Handler should run in its own fiber, not the test fiber
    handler_f.should_not eq(test_fiber)
  end

  it "should propagate cancellation to request handlers" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    handler_started = Channel(Nil).new(1)
    cancel_received = Channel(Nil).new(1)
    handler_done = Channel(Nil).new(1)

    server.request_handler(MCP::Protocol::ToolsCall) do |_params, extra|
      handler_started.send(nil)
      if ch = extra.cancel_channel
        select
        when ch.receive?
          cancel_received.send(nil)
        when timeout(5.seconds)
        end
      end
      handler_done.send(nil)
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("cancelled")] of MCP::Protocol::ContentBlock)
    end

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    spawn { server.connect(server_transport) }
    Fiber.yield

    request = MCP::Protocol::CallToolRequest.new(name: "any", arguments: {} of String => JSON::Any)
    request_id = request.id
    next unless request_id # skip if nil (should never happen)

    spawn { client_transport.send(request) }

    handler_started.receive # Wait for handler fiber to be running

    cancel = MCP::Protocol::CancelledNotification.new(request_id: request_id, reason: "test")
    client_transport.send(cancel)

    cancel_received.receive
    handler_done.receive
  end

  it "add_tool should accept annotations" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    annotations = MCP::Protocol::ToolAnnotations.new(read_only_hint: true, destructive_hint: false)

    server.add_tool("annotated-tool", "Annotated", MCP::Protocol::Tool::Input.new, annotations: annotations) { |_|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    }

    server.tool_registered?("annotated-tool").should be_true
  end

  it "add_tool should accept output_schema" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    output_schema = MCP::Protocol::Tool::Input.new(properties: {"result" => JSON::Any.new("string")} of String => JSON::Any)

    server.add_tool("output-tool", "With Output", MCP::Protocol::Tool::Input.new, output_schema: output_schema) { |_|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    }

    server.tool_registered?("output-tool").should be_true
  end

  it "Implementation should support icons" do
    icon = MCP::Protocol::Icon.new(src: "https://example.com/icon.png", mime_type: "image/png")
    icon.src.should eq("https://example.com/icon.png")
    icon.mime_type.should eq("image/png")

    impl = MCP::Protocol::Implementation.new("test", "1.0", icons: [icon])
    impl.icons.try(&.size).should eq(1)
  end

  it "Tool should support icons" do
    icon = MCP::Protocol::Icon.new("https://example.com/tool.png", "image/png", "48x48")
    tool = MCP::Protocol::Tool.new("icon-tool", MCP::Protocol::Tool::Input.new, "Tool with icon", icons: [icon])

    tool.icons.try(&.size).should eq(1)
  end

  it "Tool should support task execution modes" do
    exec = MCP::Protocol::ToolExecution.new(task_support: MCP::Protocol::TaskSupport::Optional)
    exec.task_support.should eq(MCP::Protocol::TaskSupport::Optional)

    tool = MCP::Protocol::Tool.new("task-tool", MCP::Protocol::Tool::Input.new, "Taskable", execution: exec)
    tool.execution.try(&.task_support).should eq(MCP::Protocol::TaskSupport::Optional)

    # Default should be nil execution
    default_tool = MCP::Protocol::Tool.new("default", MCP::Protocol::Tool::Input.new)
    default_tool.execution.should be_nil
  end

  it "ServerCapabilities should support extensions (SEP-1724)" do
    caps = MCP::Protocol::ServerCapabilities.new
    caps.extensions.should be_nil

    caps.with_extensions(extra: "value")
    caps.extensions.should_not be_nil
    caps.extensions.try &.has_key?("extra").should be_true
  end

  it "ClientCapabilities should support extensions (SEP-1724)" do
    caps = MCP::Protocol::ClientCapabilities.new
    caps.extensions.should be_nil

    caps.extensions = {"io.modelcontextprotocol/ui" => JSON::Any.new("enabled")} of String => JSON::Any
    caps.extensions.should_not be_nil
  end

  it "add_tool should auto-generate schema from Crystal type" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    input = MCP::Protocol::Tool::Input.from(TestToolArgs)
    server.add_tool("typed-tool", "Auto schema tool", input) { |_|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    }

    server.tool_registered?("typed-tool").should be_true
  end

  it "add_tool convenience overload should accept Crystal type directly" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("convenient-tool", "Direct type", TestToolArgs) { |_|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    }

    server.tool_registered?("convenient-tool").should be_true
  end

  it "add_tool should accept output_type for auto-generated output schema" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools))
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    server.add_tool("output-typed-tool", "With output", TestToolArgs, output_type: TestToolOutput) { |_|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("ok")] of MCP::Protocol::ContentBlock)
    }

    server.tool_registered?("output-typed-tool").should be_true
  end

  it "Tool::Output.from should generate output schema from type" do
    output = MCP::Protocol::Tool::Output.from(TestToolOutput)
    output.properties.has_key?("result").should be_true
    output.properties.has_key?("score").should be_true
  end
end

class TestToolOutput
  include JSON::Serializable
  getter result : String
  getter score : Int32?
end

class TestToolArgs
  include JSON::Serializable
  getter city : String
  getter count : Int32?
end
