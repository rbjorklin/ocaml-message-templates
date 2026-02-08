# AGENTS.md

## Eio Async Implementation

### Fiber-Based Concurrency
- Eio uses direct fiber spawning rather than promises (Lwt.t)
- Sink operations run synchronously within fiber context
- No explicit polling - relies on Eio's event loop

### Resource Management
- Eio file sinks open channels eagerly on creation (unlike Lwt lazy opening)
- Use `Eio.Path` for filesystem operations
- Console output via `Eio.Stdenv.stdout`

### Package Independence
- No code sharing with message-templates-lwt despite similar patterns
- Async_abstractions module removed - both packages implement patterns independently
- Eio-specific implementations preferred over generic abstractions

### Eio_sink.sink_fn Type Independence
- `Eio_sink.sink_fn` is separate from `Composite_sink.sink_fn` in core library
- Changes to core sink types require corresponding changes here
- Per-sink min_level filtering: wrap emit_fn with level check at creation
- Eio uses direct-style (no Lwt.t), but filtering logic is identical
