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

  def self.arg(name : String, description : String? = nil, required : Bool? = nil) : Protocol::PromptArgument
    Protocol::PromptArgument.new(name, description, required: required)
  end

  def self.prompt_msg(text : String, role : Protocol::Role = Protocol::Role::User) : Protocol::PromptMessage
    Protocol::PromptMessage.new(role, Protocol::TextContentBlock.new(text))
  end

  def self.text_resource_content(uri : String, text : String, mime_type : String? = "text/plain") : Protocol::TextResourceContents
    Protocol::TextResourceContents.new(uri: uri, text: text, mime_type: mime_type)
  end

  def self.blob_resource_content(uri : String, blob : String, mime_type : String? = nil) : Protocol::BlobResourceContents
    Protocol::BlobResourceContents.new(uri, blob, mime_type)
  end
end

require "./mcp/protocol"
require "./mcp/shared/**"
require "./mcp/server/**"
require "./mcp/client/**"
require "./mcp/annotator"
