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
