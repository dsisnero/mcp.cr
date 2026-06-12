# Changelog

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
