# Crystal MCP Parity Plan

Sources of truth:
- Go: `vendor/mcp-golang` (concurrency patterns, API surface)
- Rust: `vendor/rmcp` (protocol completeness, type definitions)

## Implemented

| Feature | Go | Rust | Crystal | Notes |
|---------|----|------|---------|-------|
| JSON-RPC message framing | Yes | Yes | Yes | Newline-delimited |
| Protocol version negotiation | Yes | Yes | Yes | 2025-06-18, 2025-03-26, 2024-11-05, 2024-10-07 |
| Server tool handlers | Yes | Yes | Yes | add_tool/remove_tool |
| Server prompt handlers | Yes | Yes | Yes | add_prompt/remove_prompt |
| Server resource handlers | Yes | Yes | Yes | add_resource/remove_resource |
| Client initialization | Yes | Yes | Yes | Handshake + version check |
| Stdio transport (server) | Yes | Yes | Yes | ReadBuffer + fiber-based |
| Stdio transport (client) | Yes | Yes | Yes | Child process I/O |
| InMemory transport | No | Yes | Yes | Test-only linked pair |
| SSE server transport | Partial | Yes | Yes | SSE connection + session mgmt |
| Streamable HTTP server | No | Yes | Yes | Stateful/stateless + JSON/SSE modes |
| Ping request/response | Yes | Yes | Yes | Auto-respond |
| Progress notifications | Yes | Yes | Yes | Token-based callback |
| Cancelled notifications | Yes | Yes | Yes | Receive only |
| Resource subscribe/unsubscribe | No | Yes | Yes | Subscription tracking |
| Completion/complete handler | No | Yes | Yes | Customizable callback |
| Logging/setLevel handler | No | Yes | Yes | Level tracking + callback |
| Sampling/createMessage handler (client) | No | Yes | Yes | Customizable callback |
| Elicitation/create handler (client) | No | Yes | Yes | Form/URL mode |
| ElicitationCompletion notification | No | Yes | Yes | |
| Task model types | No | Yes | Yes | Task, TaskStatus, results |
| Tasks capability fields | No | Yes | Yes | ClientCapabilities + ServerCapabilities |
| Annotator (macro-based) | No | No | Yes | Compile-time schema + route gen |

## Missing

### Tier 1 — Critical

| Feature | Go | Rust | Complexity | Description |
|---------|----|------|------------|-------------|
| HTTP Client Transport (Gap 1) | Yes | Yes | Medium | Cannot connect to remote MCP servers over HTTP |
| ~~Auto list-changed on register/deregister (Gap 3)~~ | Yes | Yes | Small | Done |
| ~~Spawn-per-request concurrency (Gap 8)~~ | Yes | Yes | Medium | Done |
| ~~Request cancellation propagation (Gap 9)~~ | Yes | Yes | Medium | Done — `RequestHandlerExtra#cancelled?` + cancel channel routed to handler |

### Tier 2 — High

| Feature | Go | Rust | Complexity | Description |
|---------|----|------|------------|-------------|
| ~~Convenience content constructors (Gap 4)~~ | Yes | Yes | Small | Done |
| ~~Check-registration-status (Gap 6)~~ | Yes | No | Small | Done |
| ~~Pagination logic in list handlers (Gap 7)~~ | Yes | Yes | Medium | Done |
| ~~WithAnnotations builder (Gap 5)~~ | Yes | Yes | Small | Done |
| Thread-safe registration maps (Gap 10) | Yes | Yes | Small | RW lock-protected Hash; use Crystal `sync/rw_lock` shard |

### Tier 3 — Medium

| Feature | Go | Rust | Complexity | Description |
|---------|----|------|------------|-------------|
| ~~Client capabilities accessor (Gap 11)~~ | Yes | Yes | Trivial | Done |
| Stateless HTTP server transport (Gap 12) | Yes | No | Medium | Simpler than StreamableHttpServerTransport |
| ~~Resource template registration (Gap 14)~~ | Yes | Yes | Small | Done |
| SSE client transport (Gap 15) | Partial | Yes | Medium | Event source reader for client-side SSE |
| Auto JSON Schema from handler types (Gap 2) | Yes | Yes | Large | Runtime schema generation for vanilla add_tool |

### Tier 4 — Nice-to-have

| Feature | Go | Rust | Complexity | Description |
|---------|----|------|------------|-------------|
| Handler signature validation (Gap 13) | Yes | Yes | Small | Crystal's type system mostly covers this |
| Rich prompt argument schemas (Gap 17) | Yes | Yes | Small | Per-argument descriptions from annotations |
| Elicitation schema builder | No | Yes | Large | Type-safe ElicitationSchema with enum/number/string builders |
| Tool output schema | No | Yes | Small | output_schema on Tool definition |
| Tool annotations (read_only, destructive, idempotent) | No | Yes | Small | Already have ToolAnnotations struct |
| Icon support on Implementation/Tool/Prompt | No | Yes | Small | Icon struct with src, mime_type, theme |
| Extensions type-map | No | Yes | Medium | Per-request typed extension storage |
| Tool task support (required/optional/forbidden) | No | Yes | Medium | ToolExecution + TaskSupport enum |
| SEP-1724 MCP Extensions | No | Yes | Medium | Vendor extension capability negotiation |
| Router system (ToolRouter/PromptRouter) | No | Yes | Large | Composable routing with dynamic enable/disable |

### Thread-Safe Maps Design Note

For Gap 10 (thread-safe registration maps), the Go implementation uses `sync.Map` and the Rust
implementation uses immutable data structures behind `Arc`. For Crystal, the recommended approach is:

- Use a `sync/rw_lock` (Crystal shard) for reader-writer lock protecting each `Hash`
- Alternative: use Crystal channels to serialize mutations through a single fiber
- The `@mutex` field is already added as a placeholder

This is deferred until the full fiber-per-request model (Gap 8, now done) requires it in
production transports. InMemoryTransport is synchronous so the issue doesn't surface there.

## Known Issues

### server_spec hangs/fails on synchronous request dispatch

`spec/server/server_spec.cr` has two pre-existing examples that fail/hang on `main`
(reproduced with no PR applied):

- `server_spec.cr:483` "should run request handlers synchronously in the calling fiber"
  — **fails** (~4ms). Assertion `handler_f.should_not eq(test_fiber)` expects the handler
  to run off the caller's fiber; with InMemoryTransport it runs inline in the test fiber.
- `server_spec.cr:513` "should run request handlers synchronously" — **hangs indefinitely**
  (killed at 45s, never reaches its own `timeout 5.seconds` guard).

**Root cause.** Dispatch is inline/synchronous in the caller's fiber:
`InMemoryTransport#send` -> `other._on_message.call` (no spawn,
`src/mcp/shared/in_memory_transport.cr:33-37`) -> `Protocol#on_request` ->
`handler.call` (`src/mcp/shared/protocol.cr:157`) -> response sent inline (line 160).
Test 513 never registers `client_transport.on_message`, so the inline response delivery
blocks on `@on_message_initialized.receive?` (`src/mcp/shared/transport.cr:44`), which is
never closed. `send()` never returns, so the test fiber never arms its `select` timeout.

This is consistent with the design note above: InMemoryTransport is intentionally
synchronous, but these two specs assert off-fiber dispatch against it. PR #4
("Add async MCP client request APIs") does **not** cause this — it spawns at the call site
(`call_tool_async`) as a client-side workaround.

**Fix directions.** (a) Dispatch incoming requests in their own fiber so 483 passes;
(b) guard `@on_message_initialized.receive?` so an unregistered transport can't deadlock
the sender, or have 513 register a client `on_message`.

## Quality Gates

Run before declaring any feature complete:

```bash
crystal tool format --check src spec
ameba src spec
crystal spec
```

All three must pass with zero failures.
