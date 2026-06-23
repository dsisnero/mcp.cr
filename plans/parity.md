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
| ~~Thread-safe registration maps (Gap 10)~~ | Yes | Yes | Small | Done — `@tools`/`@prompts`/`@resources`/`@resource_templates` are `Sync::Map` (dsisnero/sync-map); MT stress spec under `-Dpreview_mt -Dexecution_context` |

### Tier 3 — Medium

| Feature | Go | Rust | Complexity | Description |
|---------|----|------|------------|-------------|
| ~~Client capabilities accessor (Gap 11)~~ | Yes | Yes | Trivial | Done |
| ~~Stateless HTTP server transport (Gap 12)~~ | Yes | No | Medium | Done — covered by `StreamableHttpServerTransport` when `@stateful = false` (the default) |
| ~~Resource template registration (Gap 14)~~ | Yes | Yes | Small | Done |
| ~~SSE client transport (Gap 15)~~ | Yes | Yes | Medium | Done — SSE event parser, receive, send, endpoint extraction, reconnect with exponential backoff + Last-Event-ID |
| Auto JSON Schema from handler types (Gap 2) | Yes | Yes | Large | Runtime schema generation for vanilla add_tool |

### Tier 4 — Nice-to-have

| Feature | Go | Rust | Complexity | Description |
|---------|----|------|------------|-------------|
| Handler signature validation (Gap 13) | Yes | Yes | Small | Crystal's type system mostly covers this |
| ~~Rich prompt argument schemas (Gap 17)~~ | Yes | Yes | Small | Done — `PromptArgument` struct has `description` field |
| Elicitation schema builder | No | Yes | Large | Type-safe ElicitationSchema with enum/number/string builders |
| ~~Tool output schema~~ | No | Yes | Small | Done — `output_schema` on `Tool` |
| ~~Tool annotations (read_only, destructive, idempotent)~~ | No | Yes | Small | Done — `ToolAnnotations` struct with all hints |
| ~~Icon support on Implementation/Tool/Prompt~~ | No | Yes | Small | Done — `Icon` struct + `icons` fields on params/results |
| ~~Extensions type-map~~ | No | Yes | Medium | Done — `RequestHandlerExtra#set_extension` / `#get_extension(T)` typed accessors |
| ~~Tool task support (required/optional/forbidden)~~ | No | Yes | Medium | Done — `TaskSupport` enum + `ToolExecution` struct on `Tool` |
| ~~SEP-1724 MCP Extensions~~ | No | Yes | Medium | Done — extensions flow through initialize; spec added for negotiation round-trip |
| Router system (ToolRouter/PromptRouter) | No | Yes | Large | ToolRouter + PromptRouter + ResourceRouter done; Server wiring pending |

### Thread-Safe Maps Design Note

Gap 10 is **done**. The Go implementation uses `sync.Map` and the Rust implementation uses
immutable data structures behind `Arc`. For Crystal, the registration maps (`@tools`,
`@prompts`, `@resources`, `@resource_templates` in `src/mcp/server/server.cr`) are now backed
by `Sync::Map` from the [`dsisnero/sync-map`](https://github.com/dsisnero/sync-map) shard
(`Sync::RWLock(:unchecked)` + `Hash`), the closest Crystal analog to Go's `sync.Map`.

This matters because Gap 8 (fiber-per-request dispatch) means handlers now run on their own
fibers and can mutate registration concurrently. A bare `Hash` races under `-Dpreview_mt`
(observed: "Duplicate large block deallocation" crash from concurrent rehash). `Sync::Map`
serializes writers under the writer lock while readers run concurrently.

Coverage: `spec/server/registration_mt_spec.cr` stresses concurrent add / add+remove from
8 parallel fibers under `-Dpreview_mt -Dexecution_context`; the standard `crystal spec` run
keeps it `pending` (deterministic gate stays clean).

## Resolved Issues

### Synchronous request dispatch hang (fixed in v0.3.0)

`server_spec.cr:483`/`:513` previously failed/hung because request dispatch ran inline in the
caller's fiber. Fixed by spawning each handler in its own fiber in `Protocol#on_request`
(Gap 8, shipped in v0.3.0). Both specs now pass and the full suite is green.

## Quality Gates

Run before declaring any feature complete:

```bash
crystal tool format --check src spec
ameba src spec
crystal spec
crystal spec -Dpreview_mt -Dexecution_context   # MT-safety gate (Gap 10)
```

All must pass with zero failures.
