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

  # Full CRUD integration: add_tool → tools/list → tools/call → remove_tool

  it "add_tool, tools/list, tools/call, remove_tool — full pet CRUD lifecycle" do
    server_options = MCP::Server::ServerOptions.new(
      MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools(true).tools)
    )
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    tool_names = [] of String
    server.request_handler(MCP::Protocol::ToolsList) do |_request, _|
      tools = tool_names.map { |name|
        MCP::Protocol::Tool.new(name: name, description: "A tool", input_schema: MCP::Protocol::Tool::Input.new)
      }
      MCP::Protocol::ListToolsResult.new(tools: tools, next_cursor: nil)
    end

    pet_input = MCP::Protocol::Tool::Input.new(
      properties: {"name" => JSON::Any.new({"type" => JSON::Any.new("string")})},
      required: ["name"]
    )

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    received = Channel(MCP::Protocol::JSONRPCMessage).new(3)
    client_transport.on_message { |msg| received.send(msg) }

    spawn { server.connect(server_transport) }
    Fiber.yield

    # 1. Initially empty
    client_transport.send(MCP::Protocol::ListToolsRequest.new)
    msg = received.receive
    tools = msg.as(MCP::Protocol::JSONRPCResponse).result.as(MCP::Protocol::ListToolsResult).tools
    tools.should be_empty

    # 2. Add a tool (create pet)
    server.add_tool("create_pet", "Create a new pet", pet_input) { |_req|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("created fluffy")] of MCP::Protocol::ContentBlock)
    }
    tool_names << "create_pet"

    # 3. List tools — pet tool appears
    client_transport.send(MCP::Protocol::ListToolsRequest.new)
    msg = received.receive
    tools = msg.as(MCP::Protocol::JSONRPCResponse).result.as(MCP::Protocol::ListToolsResult).tools
    tools.size.should eq(1)
    tools.first.name.should eq("create_pet")

    # 4. Call the tool (create fluffy)
    client_transport.send(MCP::Protocol::CallToolRequest.new(
      name: "create_pet",
      arguments: {"name" => JSON::Any.new("fluffy")}
    ))
    msg = received.receive
    msg.should be_a(MCP::Protocol::JSONRPCResponse)

    # 5. Add a second tool (list pets)
    server.add_tool("list_pets", "List all pets", MCP::Protocol::Tool::Input.new) { |_req|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("[]")] of MCP::Protocol::ContentBlock)
    }
    tool_names << "list_pets"

    client_transport.send(MCP::Protocol::ListToolsRequest.new)
    msg = received.receive
    tools = msg.as(MCP::Protocol::JSONRPCResponse).result.as(MCP::Protocol::ListToolsResult).tools
    tools.size.should eq(2)

    # 6. Delete pets (remove tools)
    server.remove_tool("create_pet").should be_true
    server.remove_tool("list_pets").should be_true
    tool_names.clear

    # 7. List tools — empty again
    client_transport.send(MCP::Protocol::ListToolsRequest.new)
    msg = received.receive
    tools = msg.as(MCP::Protocol::JSONRPCResponse).result.as(MCP::Protocol::ListToolsResult).tools
    tools.size.should eq(0)
  end

  it "add_tool raises when tools capability is not supported" do
    server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new)
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    pet_input = MCP::Protocol::Tool::Input.new(
      properties: {"name" => JSON::Any.new({"type" => JSON::Any.new("string")})},
      required: ["name"]
    )
    expect_raises(Exception, "Server does not support tools capability") do
      server.add_tool("create_pet", "Create a new pet", pet_input) { |_req|
        MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("created")] of MCP::Protocol::ContentBlock)
      }
    end
  end

  it "tools/call with unknown tool name returns method_not_found error" do
    server_options = MCP::Server::ServerOptions.new(
      MCP::Server::ServerCapabilities.new(tools: MCP::Server::ServerCapabilities.new.with_tools.tools)
    )
    impl = MCP::Protocol::Implementation.new(name: "test server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
    received = Channel(MCP::Protocol::JSONRPCMessage).new(1)
    client_transport.on_message { |msg| received.send(msg) }

    spawn { server.connect(server_transport) }
    Fiber.yield

    client_transport.send(MCP::Protocol::CallToolRequest.new(
      name: "nonexistent_tool",
      arguments: {} of String => JSON::Any
    ))
    msg = received.receive
    msg.should be_a(MCP::Protocol::JSONRPCError)
  end
end
