require "../spec_helper"

describe MCP::Client::HttpClientTransport do
  it "stores endpoint and base_url" do
    transport = MCP::Client::HttpClientTransport.new("/messages")
    transport = transport.with_base_url("http://localhost:8080")
    transport.with_header("X-Custom", "value")

    transport.endpoint.should eq("/messages")
    transport.base_url.should eq("http://localhost:8080")
  end

  it "start is a no-op" do
    transport = MCP::Client::HttpClientTransport.new("/mcp")
    transport.start
  end

  it "serializes JSON-RPC messages to valid JSON" do
    ping = MCP::Protocol::PingRequest.new
    json = ping.to_json

    json.should contain("ping")
    json.should contain("2.0")
  end

  it "accepts a custom HTTP client" do
    client = HTTP::Client.new("localhost", 9999)
    transport = MCP::Client::HttpClientTransport.new("/mcp")
    transport = transport.with_client(client)

    transport.http_client.should_not be_nil
  end
end
