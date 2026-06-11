require "json"
require "json-schema"
require "./ext/atomic"

module MCP
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  def self.text_content(text : String) : Protocol::TextContentBlock
    Protocol::TextContentBlock.new(text)
  end

  def self.image_content(data : String, mime_type : String) : Protocol::ImageContentBlock
    Protocol::ImageContentBlock.new(data: data, mime_type: mime_type)
  end

  def self.tool_result(text : String) : Protocol::CallToolResult
    Protocol::CallToolResult.new([Protocol::TextContentBlock.new(text)] of Protocol::ContentBlock)
  end

  def self.tool_result(*contents : Protocol::ContentBlock) : Protocol::CallToolResult
    Protocol::CallToolResult.new(contents.to_a)
  end

  def self.resource_result(uri : String, content : String, mime_type : String = "text/plain") : Protocol::ReadResourceResult
    Protocol::ReadResourceResult.new(
      contents: [Protocol::TextResourceContents.new(text: content, uri: uri, mime_type: mime_type)] of Protocol::ResourceContents
    )
  end
end

require "./mcp/protocol"
require "./mcp/shared/**"
require "./mcp/server/**"
require "./mcp/client/**"
require "./mcp/annotator"
