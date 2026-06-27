# Changelog

## [0.5.3] - 2026-06-27

### Added

- **Async request handler registration**: `Protocol#request_handler_async(method, &block)` registers a handler that returns `Channel(AsyncResult(Result))`. The protocol `select`s between the result channel and the request's cancel channel, owning the wait, cancellation, and response-send lifecycle. Mirrors Rust rmcp's `AsyncTool` pattern.

- **Async tool handler registration**: `Server#add_tool_async(name, description, schema, &handler)` and typed overloads register async tool handlers matching the existing `add_tool` API surface. Handlers receive both `CallToolRequestParams` and `RequestHandlerExtra` and return `Channel(AsyncResult(CallToolResult))`. The wrapper `select`s on the async result channel vs the cancel channel, then sends the appropriate JSON-RPC response.

- **ToolRouter async support**: `ToolRouter#add_tool_async(name, &handler)` registers async tool handlers with the same enable/disable/remove/call semantics as sync handlers. Async tools are wrapped into sync handlers internally via cancel-aware channel select.

### Changed

- **`RegisteredTool` handler signature extended**: The handler proc now receives both `CallToolRequestParams` and `RequestHandlerExtra` (previously only `CallToolRequestParams`). Existing sync `add_tool` overloads wrap their handlers automatically — no user-facing API change. `handle_call_tool` threads the `extra` through to tool handlers, enabling cancellation awareness.

## [0.5.2] - 2026-06-23

### Fixed

- **Router maps made thread-safe**: `ToolRouter`, `PromptRouter`, and `ResourceRouter` internal `@handlers` and `@disabled` maps now use `Sync::XMap` instead of bare `Hash`/`Set`. Concurrent `add_tool`/`remove_tool`/`enable`/`disable`/`call` from parallel fibers under `-Dpreview_mt` is now safe.
- **Router concurrency spec**: `spec/server/router_concurrency_mt_spec.cr` exercises concurrent add/remove/call and enable/disable/call (2 specs).

## [0.5.1] - 2026-06-23

### Fixed

- **Client protocol correlation maps made thread-safe**: Replaced bare `Hash` maps in `MCP::Shared::Protocol` (`@response_handlers`, `@progress_handlers`, `@request_cancellers`) with `Sync::XMap` (CLHT backend).  Under `-Dpreview_mt -Dexecution_context` concurrent `call_tool` from multiple fibers previously raced on these maps — concurrent `Hash#[]=` / `#delete` / iteration could corrupt the bucket array, drop entries, or crash.
- **Atomic claim-and-remove for request resolution**: `on_response` and the timeout `cancel` closure now use `load_and_delete` instead of a two-step `[]?` + `delete`, preventing a double-completion race where both the response pump and a timeout fiber send to the same result channel.
- **Atomic canceller take**: `on_notification` cancellation handler uses `load_and_delete` instead of `[]?` + `close` + `delete`.
- **`Client` is now safe for concurrent use by multiple fibers** — documented in README.  `call_tool`/`request`/`call_tool_async` may be called from many fibers on a single client with no external serialization.
- **Concurrency spec**: `spec/client/client_concurrency_mt_spec.cr` exercises fan-out + timeout-constraint paths under concurrent fibers (193/0/0/1-pending).

## [0.5.0] - 2026-06-23

### Changed

- **Registration maps switched to `Sync::XMap`**: Replaced `Sync::Map` (RWLock + Hash) with `Sync::XMap` (CLHT backend) from `dsisnero/sync-map` 0.1.4 for the four registration maps in `Server` (`@tools`, `@prompts`, `@resources`, `@resource_templates`).  `XMap` is 1.9x faster for small mixed read/write workloads per the sync-map benchmarks (64.6M vs 34.8M ops/s at size 100).  Full Crystal `Hash` surface is now available on `XMap` as of sync-map 0.1.4.

## [0.4.0] - 2026-06-23

### Added

- **Thread-safe registration maps (Gap 10)**: `@tools`, `@prompts`, `@resources`, and `@resource_templates` in `Server` are now backed by `Sync::Map` from `dsisnero/sync-map`, providing concurrent-safe mutations under fiber-per-request dispatch. Includes a multi-threaded stress spec (`-Dpreview_mt -Dexecution_context`).

- **SSE client transport (Gap 15)**: `MCP::Client::SseClientTransport` for connecting to MCP servers over Server-Sent Events. Full lifecycle: SSE event stream parser (`MCP::Shared::SSEEvent`), HTTP GET for receive path, endpoint-url extraction from control frames, HTTP POST for send path, and automatic reconnect with exponential backoff and `Last-Event-ID` tracking.

- **Auto-generated JSON Schema from typed handlers (Gap 2)**: `Server#add_tool` overload accepting `Proc(T -> CallToolResult)` where `T : JSON::Serializable`. The input schema is auto-generated from `T` via the `json-schema` shard (`Tool::Input.from(T.class)`), and the handler receives a fully-deserialized typed input instead of raw `CallToolRequestParams`.

- **Elicitation schema builder**: Type-safe fluent builders ported from Rust rmcp for constructing MCP 2025-06-18 compliant elicitation schemas. Includes `StringSchema` (email/uri/date/date-time formats), `NumberSchema`, `IntegerSchema`, `BooleanSchema`, `EnumSchema` (single/multi-select, titled/untitled), `PrimitiveSchema` union, and `ElicitationSchema` / `ElicitationSchemaBuilder` with convenience methods (`required_email`, `optional_integer`, etc.).

- **Router system**: `ToolRouter`, `PromptRouter`, and `ResourceRouter` provide name-based dispatch with enable/disable and introspection. `Server#tool_router`, `#prompt_router`, and `#resource_router` lazily expose views over the registered handlers.

- **Typed request-handler extension accessors (Extensions type-map)**: `RequestHandlerExtra#set_extension(key, value)` and `#get_extension(key, T)` for type-safe per-request extension storage with automatic JSON serialization/deserialization.

- **SEP-1724 MCP Extensions**: Extensions capability negotiation now has spec coverage confirming extensions flow through the initialize handshake.

### Changed

- **Fixed pre-existing block-passing bugs**: `Server#add_prompt` overloads now correctly pass `Proc` handlers as blocks (`&handler`), resolving latent compilation issues uncovered by the Router wiring.

### Fixed

- **Parity plan reconciled**: Stale "Missing" entries for already-implemented features (HTTP Client Transport, Stateless HTTP, Tool output schema, Tool annotations, Icon support, Rich prompt argument schemas, Tool task support) are now correctly marked done in `plans/parity.md`.

## [0.3.0] - 2026-06-22

### Added

- **Async client request APIs**: `MCP::Client::Client#call_tool_async`, `MCP::Shared::Protocol#request_async`, and `MCP::Shared::AsyncResult(T)`. A single client can now issue overlapping, non-blocking tool calls — each returns a `Channel` carrying an `AsyncResult` (`#unwrap` raises on error, `#success?` to check). ([#4](https://github.com/dsisnero/mcp.cr/pull/4))

- **Request cancellation propagation (Gap 9)**: `MCP::Shared::RequestHandlerExtra#cancelled?` reflects a closed cancel channel, so request handlers can observe client-initiated cancellation mid-flight.

- **Tool CRUD integration tests**: full pet lifecycle (add_tool → tools/list → tools/call → remove_tool), capability-not-supported errors, and unknown-tool errors. Plus concurrent/overlapping handler specs.

### Changed

- **Concurrent server request dispatch**: `MCP::Shared::Protocol#on_request` now runs each handler in its own fiber (spawn-per-request) with inflight tracking, replacing the previous inline/synchronous dispatch. Handlers can overlap, and the in-memory transport caller is no longer blocked by inline response delivery.

### Fixed

- **Idempotent transport close**: `InMemoryTransport` and `StreamableHttpServerTransport` now guard against double-close (`@closed` flag), preventing errors on repeated `close()`.

- **Stale inflight signal**: eliminated a stale `inflight_zero` signal by draining with a while-loop in the inflight-request tracker.

## [0.2.1] - 2026-06-12

### Fixed

- **StreamableHttpServerTransport race condition**: JSON response mode (`enable_json_response: true`) had a fiber timing issue where `handle_post_request` returned before the spawned handler fiber wrote the response, causing data loss or truncated HTTP responses. Fixed by implementing channel-based synchronization — `handle_post_request` now blocks on a `Channel` until `send()` delivers the assembled response, matching the Go (`mcp-golang`) and Rust (`rmcp`) vendor patterns. Added timeout via `DEFAULT_REQUEST_TIMEOUT` (60s). ([#1](https://github.com/dsisnero/mcp.cr/pull/1))

- **Batch JSON-RPC POST parsing**: `parse_body` in `StreamableHttpServerTransport` had an unreachable `when Array` branch — `JSON.parse` always returns `JSON::Any`, so batch message arrays were never parsed. Fixed by testing `json.raw.is_a?(Array)`.

- **StdioServerTransport drain-before-close**: Read fiber now closes `read_channel` on EOF instead of calling `close()` directly; processing fiber drains remaining bytes and calls `close()` only after draining. Prevents in-flight message loss when stdin closes, matching the Rust `rmcp` drain pattern. ([#1](https://github.com/dsisnero/mcp.cr/pull/1))

- **Client return type casts**: Client methods (`get_prompt`, `list_tools`, `list_resources`, etc.) now use `.as?(SpecificType)` casts to preserve nullable subtype return types.

### Added

- StreamableHttpServerTransport specs: tests for JSON response delivery (Ping, slow handler with 100ms delay, batch POST, notification-only). Validates that HTTP responses are written before `handle_post_request` returns.

- StdioServerTransport specs: tests for EOF drain (all messages processed before close) and close-after-drain ordering.

## [0.2.0] - 2025-06

### Added

- Annotation-based MCP Server development
- SSE & Streamable HTTP transports with specs & samples
- Protocol types and handlers (subscribe, completion, logging, elicitation, task model, icons, sampling)
- Server enhancements (auto-notifications, registration checks, templates, pagination, annotations)
- Client enhancements (sampling, elicitation, spawn-per-request, cancellation)
- HTTP Client Transport (Gap 1)
- JSON Schema auto-generation from Crystal types via json-schema shard (Gap 2)
- SEP-1724 MCP Extensions
- Tool output schema auto-generation
- Convenience constructors (prompt_msg, text_resource_content, blob_resource_content)
- Resource template URI matching and auto-notifications
- Extensions map on RequestHandlerExtra for typed request context
- `Server#clear_all` for resetting all registrations
- `MCP.prompt_response` convenience constructor
- Batch resource template removal
