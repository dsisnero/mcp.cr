require "http/client"
require "../shared"

module MCP::Client
  class HttpClientTransport < MCP::Shared::AbstractTransport
    getter endpoint : String
    getter base_url : String
    getter headers : Hash(String, String)
    property http_client : HTTP::Client?

    def initialize(@endpoint : String)
      super()
      @base_url = ""
      @headers = {} of String => String
    end

    def with_base_url(url : String) : self
      @base_url = url
      self
    end

    def with_header(key : String, value : String) : self
      @headers[key] = value
      self
    end

    def with_client(client : HTTP::Client) : self
      @http_client = client
      self
    end

    def start
      # Stateless HTTP transport - no persistent connection to start
    end

    def send(message : MCP::Protocol::JSONRPCMessage)
      json_body = message.to_json
      url = "#{@base_url}#{@endpoint}"

      uri = URI.parse(url)
      http_headers = HTTP::Headers.new
      http_headers["Content-Type"] = "application/json"
      @headers.each { |k, v| http_headers[k] = v }

      response = @http_client.try do |client|
        client.post(uri.path, headers: http_headers, body: json_body)
      end || begin
        client = HTTP::Client.new(uri)
        client.post(uri.path, headers: http_headers, body: json_body)
      end

      if response.status_code != 200
        body = response.body || ""
        raise "HTTP #{response.status_code}: #{body}"
      end

      if response.body && !response.body.empty?
        msg = MCP::Protocol::JSONRPCMessage.from_json(response.body)
        _on_message.call(msg)
      end
    rescue ex : IO::Error
      raise ex
    end

    def close
      _on_close.call
    end
  end
end
