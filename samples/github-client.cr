#!/usr/bin/env crystal
#
# MCP client example: list your GitHub repositories via the official
# GitHub MCP server (`@modelcontextprotocol/server-github`).
#
# Prerequisites:
#   npm install -g @modelcontextprotocol/server-github
#   export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."
#
# Run:
#   crystal run samples/github-client.cr

require "../src/mcp"

token = ENV["GITHUB_PERSONAL_ACCESS_TOKEN"]?
abort "Set GITHUB_PERSONAL_ACCESS_TOKEN environment variable" unless token

puts "Connecting to GitHub MCP server..."

client = MCP::Client::Client.new(
  client_info: MCP::Protocol::Implementation.new("github-client", "1.0"),
  client_options: MCP::Client::ClientOptions.new(
    capabilities: MCP::Protocol::ClientCapabilities.new
  )
)

process = Process.new(
  "npx",
  args: ["-y", "@modelcontextprotocol/server-github"],
  input: :pipe,
  output: :pipe,
  env: {"GITHUB_PERSONAL_ACCESS_TOKEN" => token}
)

transport = MCP::Client::StdioClientTransport.new(
  input: process.output,
  output: process.input
)
client.connect(transport)

# List available tools (sanity check)
tools_result = client.list_tools
if tools = tools_result
  puts "Available tools:"
  tools.tools.each { |t| puts "  - #{t.name}: #{t.description}" }
  puts
end

# List repositories
puts "Fetching your repositories..."
result = client.call_tool(
  "list_repositories",
  {} of String => JSON::Any
)

if call_result = result.as?(MCP::Protocol::CallToolResult)
  call_result.content.each do |block|
    puts block.as(MCP::Protocol::TextContentBlock).text if block.is_a?(MCP::Protocol::TextContentBlock)
  end
end

client.close
process.wait
puts "Done."
