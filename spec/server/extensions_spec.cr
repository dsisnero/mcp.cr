require "../spec_helper"

describe MCP::Server::Server do
  it "includes extensions in initialize result when configured" do
    caps = MCP::Server::ServerCapabilities.new.with_extensions(my_extension: "v1")
    server_options = MCP::Server::ServerOptions.new(caps)
    impl = MCP::Protocol::Implementation.new(name: "ext-server", version: "1.0")
    server = MCP::Server::Server.new(impl, server_options)

    client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair

    response = Channel(MCP::Protocol::JSONRPCMessage).new(1)
    client_transport.on_message { |msg| response.send(msg) }

    spawn { server.connect(server_transport) }
    Fiber.yield

    client_transport.send(MCP::Protocol::InitializeRequest.new(
      MCP::Protocol::InitializeRequestParams.new(
        protocol_version: MCP::Protocol::LATEST_PROTOCOL_VERSION,
        capabilities: MCP::Protocol::ClientCapabilities.new,
        client_info: MCP::Protocol::Implementation.new("ext-client", "1.0")
      )
    ))

    resp = response.receive
    result = resp.as(MCP::Protocol::JSONRPCResponse).result.as(MCP::Protocol::InitializeResult)
    result.capabilities.extensions.should_not be_nil
    ext = result.capabilities.extensions
    ext.not_nil!["my_extension"]?.to_s.should eq("v1")
  end
end
