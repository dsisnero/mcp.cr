require "json"
require "log"
require "sync-map/xmap"
require "./transport"
require "../protocol/**"

module MCP::Shared
  class ProtocolOptions
    include JSON::Serializable

    property? enforce_strict_capabilities : Bool
    property timeout : Time::Span

    def initialize(@enforce_strict_capabilities, @timeout = DEFAULT_REQUEST_TIMEOUT)
    end
  end

  class RequestOptions
    include JSON::Serializable
    property on_progress : ProgressCallback?
    property timeout : Float64

    def initialize(@on_progress = nil, @timeout = DEFAULT_REQUEST_TIMEOUT)
    end
  end

  class RequestHandlerExtra
    include JSON::Serializable::Unmapped
    property cancel_channel : Channel(Bool)?
    property extensions : Hash(String, JSON::Any)

    def initialize
      @extensions = Hash(String, JSON::Any).new
    end

    # Check whether the request was cancelled by the client.
    def cancelled? : Bool
      @cancel_channel.try(&.closed?) || false
    end

    # Store a typed value in the extensions map, serialized as JSON.
    # Use in request handlers to attach per-request context.
    #
    # ```
    # extra.set_extension("trace_id", some_struct)
    # ```
    def set_extension(key : String, value)
      @extensions[key] = JSON.parse(value.to_json)
    end

    # Retrieve a typed value by key, deserializing from JSON.
    # Returns `nil` if the key is missing or the value doesn't match `T`.
    #
    # ```
    # trace = extra.get_extension("trace_id", TraceContext)
    # ```
    def get_extension(key : String, t : T.class) : T? forall T
      raw = @extensions[key]?
      return unless raw

      begin
        T.from_json(raw.to_json)
      rescue ex : JSON::ParseException
        nil
      end
    end
  end

  abstract class Protocol
    Log = ::Log.for(self)

    property transport : Transport?
    @request_handlers = {} of String => (JSONRPCRequest, RequestHandlerExtra) -> Result?
    @notification_handlers = {} of String => JSONRPCNotification ->
    @response_handlers : Sync::XMap(RequestId, Proc(JSONRPCResponse?, Exception?, Nil)) = Sync::XMap(RequestId, Proc(JSONRPCResponse?, Exception?, Nil)).new
    @progress_handlers = Sync::XMap(RequestId, ProgressCallback).new
    @request_cancellers = Sync::XMap(RequestId, Channel(Bool)).new
    property fallback_request_handler : ((JSONRPCRequest, RequestHandlerExtra) -> Result?)?
    property fallback_notification_handler : (JSONRPCNotification ->)?

    def initialize(@options : ProtocolOptions? = nil)
      notification_handler(MCP::Protocol::NotificationsProgress) do |notification|
        on_progress(notification.as(MCP::Protocol::ProgressNotificationParams))
      end

      request_handler(MCP::Protocol::Ping) do |_request, _extra|
        EmptyResult.new
      end
    end

    def on_close
      # To be implemented by subclasses
    end

    def on_error(error : Exception)
      # To be implemented by subclasses
    end

    def connect(transport : Transport)
      @transport = transport

      transport.on_close { do_close }
      transport.on_error { |error| on_error(error) }

      transport.on_message do |message|
        case message
        when JSONRPCResponse
          on_response(message, nil)
        when JSONRPCRequest
          on_request(message)
        when JSONRPCNotification
          on_notification(message)
        when JSONRPCError
          on_response(nil, message)
        end
      end

      transport.start
    end

    private def do_close
      @response_handlers.clear
      @progress_handlers.clear
      @request_cancellers.each { |_, ch| ch.close }
      @request_cancellers.clear
      @transport = nil
      on_close

      error = MCP::Protocol::MCPError.new(:connection_closed, "Connection closed")
      @response_handlers.each do |_, handler|
        handler.call(nil, error)
      end
    end

    private def on_notification(notification : JSONRPCNotification)
      Log.trace { "Received notification: #{notification.method}" }

      # Handle cancellation by closing the request's cancel channel
      if notification.method == MCP::Protocol::NotificationsCancelled
        if params = notification.params.as?(MCP::Protocol::CancelledNotificationParams)
          channel, loaded = @request_cancellers.load_and_delete(params.request_id)
          channel.try &.close if loaded
        end
      end

      handler = @notification_handlers[notification.method]? || @fallback_notification_handler
      return unless handler

      begin
        handler.call(notification)
      rescue error
        Log.error(exception: error) { "Error handling notification: #{notification.method}" }
        on_error(error)
      end
    end

    private def on_request(request : JSONRPCRequest)
      Log.trace { "Received request: #{request.method} (id: #{request.id})" }

      handler = @request_handlers[request.method]? || @fallback_request_handler
      unless handler
        Log.trace { "No handler found for request: #{request.method}" }
        begin
          @transport.try &.send(
            MCP::Protocol::JSONRPCError.new(
              request.id,
              :method_not_found,
              "Server does not support #{request.method}"
            )
          )
        rescue error
          Log.error(exception: error) { "Error sending method not found response" }
          on_error(error)
        end
        return
      end

      transport = @transport
      cancel_channel = Channel(Bool).new
      rid = request.id
      @request_cancellers[rid] = cancel_channel if rid
      extra = RequestHandlerExtra.new
      extra.cancel_channel = cancel_channel

      transport.try &.begin_request

      spawn do
        begin
          resp = handler.call(request, extra)
          Log.trace { "Request handled successfully: #{request.method} (id: #{request.id})" }
          if result = resp
            transport.try &.send(
              JSONRPCResponse.new(id: request.id, result: result)
            )
          else
            transport.try &.send(
              JSONRPCError.new(
                request.id,
                :internal_error,
                "Internal error: Handler returned no result"
              )
            )
          end
        rescue error
          Log.error(exception: error) { "Error handling request: #{request.method} (id: #{request.id})" }

          begin
            transport.try &.send(
              JSONRPCError.new(
                request.id,
                :internal_error,
                error.message || "Internal error"
              )
            )
          rescue ex
            Log.error(exception: ex) { "Failed to send error response" }
          end
        ensure
          @request_cancellers.delete(rid) if rid
          transport.try &.end_request
        end
      end
    end

    private def on_progress(notification : MCP::Protocol::ProgressNotificationParams)
      Log.trace { "Received progress notification: token=#{notification.progress_token}, progress=#{notification.progress}/#{notification.total}" }

      progress = notification.progress
      total = notification.total
      message = notification.message
      progress_token = notification.progress_token

      handler = @progress_handlers[progress_token]?
      unless handler
        error = Exception.new("Received a progress notification for an unknown token: #{notification.to_json}")
        Log.error { error.message }
        on_error(error)
        return
      end

      handler.call(MCP::Protocol::Progress.new(progress, total, message))
    end

    private def on_response(response : JSONRPCResponse?, error : MCP::Protocol::JSONRPCError?)
      message_id = response.try &.id
      return on_error(Exception.new("Unknown message ID: #{response}")) unless message_id

      handler, loaded = @response_handlers.load_and_delete(message_id)
      return on_error(Exception.new("Unknown message ID: #{response}")) unless loaded

      @progress_handlers.delete(message_id)

      if response
        handler.not_nil!.call(response, nil)
      elsif error
        handler.not_nil!.call(nil, MCP::Protocol::MCPError.new(
          error.error.code,
          error.error.message,
          error.error.data
        ))
      end
    end

    def close
      @transport.try &.close
    end

    def request_async(request : JSONRPCRequest, options : RequestOptions? = nil) : Channel(AsyncResult(Result))
      channel = Channel(AsyncResult(Result)).new(1)

      spawn do
        begin
          channel.send(AsyncResult(Result).new(value: self.request(request, options)))
        rescue ex
          channel.send(AsyncResult(Result).new(error: ex))
        ensure
          channel.close
        end
      end

      channel
    end

    abstract def assert_capability_for_method(method : String)
    abstract def assert_notification_capability(method : String)
    abstract def assert_request_handler_capability(method : String)

    # ameba:disable Metrics/CyclomaticComplexity
    def request(request : JSONRPCRequest, options : RequestOptions? = nil) : Result
      Log.trace { "Sending request: #{request.method}" }

      transport = @transport || raise "Not connected"
      @options.try do |opt|
        assert_capability_for_method(request.method) if opt.enforce_strict_capabilities?
      end

      message = request
      # ameba:disable Lint/NotNil
      message_id = message.id.not_nil!

      if progress_cb = options.try &.on_progress
        Log.trace { "Registering progress handler for request id: #{message_id}" }
        @progress_handlers[message_id] = progress_cb
      end

      result_channel = Channel(Result | Exception).new(1)

      @response_handlers[message_id] = ->(response : JSONRPCResponse?, error : Exception?) {
        if error
          result_channel.send(error)
        elsif response.is_a?(MCP::Protocol::JSONRPCError)
          result_channel.send(Exception.new(response.error.to_json))
        else
          begin
            if result = response.as?(MCP::Protocol::JSONRPCResponse)
              result_channel.send(result.result)
            else
              result_channel.send(Exception.new("No result in response"))
            end
          rescue e
            result_channel.send(e)
          end
        end
      }

      cancel = ->(reason : Exception) {
        _, loaded = @response_handlers.load_and_delete(message_id)
        return unless loaded

        @progress_handlers.delete(message_id)

        notification = MCP::Protocol::CancelledNotification.new(
          request_id: message_id,
          reason: reason.message || "Unknown"
        )

        transport.send(notification)
        result_channel.send(reason)
      }

      timeout = options.try(&.timeout) || DEFAULT_REQUEST_TIMEOUT

      begin
        transport_chan = Channel(Bool).new(1)
        spawn do
          transport.send(message)
          transport_chan.send(true)
        end
        select
        when transport_chan.receive
          Log.trace { "Sent request message with id: #{message_id}" }
        when timeout(timeout)
          timeout_error = MCP::Protocol::MCPError.new(
            code: :request_timeout,
            message: "Request timed out",
            data: {"timeout" => JSON::Any.new(timeout.total_milliseconds.to_i)}
          )

          Log.error { "Request timed out after #{timeout.total_milliseconds.to_i}ms: #{request.method}" }
          cancel.call(timeout_error)
          raise timeout_error
        end

        # Wait for response
        select
        when result = result_channel.receive
          case result
          when Exception
            raise result
          else
            result
          end
        when timeout(timeout)
          timeout_error = MCP::Protocol::MCPError.new(
            code: :request_timeout,
            message: "Request timed out",
            data: {"timeout" => JSON::Any.new(timeout.total_milliseconds.to_i)}
          )

          Log.error { "Request timed out after #{timeout.total_milliseconds.to_i}ms: #{request.method}" }
          cancel.call(timeout_error)
          raise timeout_error
        end
      rescue ex : Exception
        cancel.call(ex)
        raise ex
      end
    end

    def notification(notification : JSONRPCNotification)
      Log.trace { "Sending notification: #{notification.method}" }
      transport = @transport || raise "Not connected"
      assert_notification_capability(notification.method)

      transport.send(notification)
    end

    def request_handler(method : String, &block : (RequestParams, RequestHandlerExtra) -> Result?)
      assert_request_handler_capability(method)

      @request_handlers[method] = ->(request : JSONRPCRequest, extra : RequestHandlerExtra) {
        if request.responds_to?(:params)
          block.call(request.params, extra)
        else
          EmptyResult.new
        end
      }
    end

    # Register an async request handler that returns a
    # `Channel(AsyncResult(Result))`. The protocol waits on the channel
    # (or the request's cancel channel) and sends the appropriate
    # JSON-RPC response.
    #
    # ```
    # protocol.request_handler_async("my/method") do |params, extra|
    #   channel = Channel(AsyncResult(Result)).new(1)
    #   spawn do
    #     channel.send(AsyncResult(Result).new(value: some_result))
    #     channel.close
    #   end
    #   channel
    # end
    # ```
    def request_handler_async(method : String, &block : (RequestParams, RequestHandlerExtra) -> Channel(AsyncResult(Result)))
      assert_request_handler_capability(method)

      @request_handlers[method] = ->(request : JSONRPCRequest, extra : RequestHandlerExtra) {
        if request.responds_to?(:params)
          result_channel = block.call(request.params, extra)

          if cancel_ch = extra.cancel_channel
            select_ch = Channel(Bool).new

            spawn do
              cancel_ch.receive?
              select_ch.close
            end

            select
            when async_result = result_channel.receive?
              unless async_result
                raise MCP::Protocol::MCPError.new(:internal_error, "Handler closed result channel without a result")
              end
              if async_result.success?
                async_result.value
              else
                raise async_result.error.not_nil!
              end
            when select_ch.receive?
              raise MCP::Protocol::MCPError.new(:invalid_request, "Request cancelled")
            end
          else
            async_result = result_channel.receive?
            unless async_result
              raise MCP::Protocol::MCPError.new(:internal_error, "Handler closed result channel without a result")
            end
            if async_result.success?
              async_result.value
            else
              raise async_result.error.not_nil!
            end
          end
        else
          EmptyResult.new
        end
      }
    end

    def remove_request_handler(method : String)
      @request_handlers.delete(method)
    end

    def notification_handler(method : String, &block : MCP::Protocol::Notification? ->)
      @notification_handlers[method] = ->(notification : JSONRPCNotification) {
        block.call(notification.params)
      }
    end

    def remove_notification_handler(method : String)
      @notification_handlers.delete(method)
    end
  end
end
