# AGENTS.md

## Lwt Async Implementation

### Pattern Consistency
- Lwt and Eio packages share conceptual patterns but implement independently
- No shared code between Lwt and Eio packages - intentional separation
- Async_abstractions module was removed - was unused documentation-only stubs

### Sink Implementation Notes
- Lwt file sinks open channels lazily (on first write)
- Eio file sinks open channels eagerly (on creation)
- Different resource management approaches require separate implementations

### Lwt_sink.sink_fn Type Independence
- `Lwt_sink.sink_fn` is separate from `Composite_sink.sink_fn` in core library
- Changes to core sink types require corresponding changes here
- Per-sink min_level filtering: wrap emit_fn with level check at creation
- Lwt uses `Lwt.return ()` for skipped events, sync sinks use `()`
