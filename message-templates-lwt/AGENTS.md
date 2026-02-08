# Project Overview

Lwt async concurrency support for OCaml Message Templates. This package provides monadic async logging with Lwt promises, allowing non-blocking log operations in Lwt-based applications. Implements the same patterns as the core library but with `unit Lwt.t` return types.

## Repository Structure

- **`message-templates-lwt/`** - This directory: Lwt async package
  - `lib/` - Lwt-specific implementations
    - `lwt_logger.ml` - Async logger interface
    - `lwt_configuration.ml` - Async configuration builder
    - `lwt_file_sink.ml` - Async file operations
    - `lwt_console_sink.ml` - Async console output
    - `lwt_sink.ml` - Lwt sink type definitions
    - `messageTemplates_lwt.ml` - Module exports
  - `examples/` - Lwt usage examples
  - `test/` - Lwt-specific tests

## Build & Development Commands

```bash
# Build Lwt package
dune build message-templates-lwt/

# Install dependencies
opam install lwt

# Run Lwt tests
dune exec message-templates-lwt/test/test_lwt_logger.exe

# Run Lwt examples
dune exec message-templates-lwt/examples/lwt_example.exe

# Build all packages including Lwt
dune build @install
```

## Code Style & Conventions

### Lwt Naming
- Prefix modules with `lwt_` (e.g., `lwt_logger.ml`, `lwt_file_sink.ml`)
- Use `Lwt.return ()` for skipped events in filtering
- Keep same API shape as sync version but with Lwt.t wrapper

### Monadic Style
```ocaml
(* Use let* for Lwt binding *)
let* () = Lwt_logger.information logger "Message" [] in
let* () = Lwt_logger.debug logger "Debug info" [] in
Lwt.return ()
```

### Error Handling
```ocaml
(* Lwt catches exceptions - handle explicitly *)
Lwt.catch
  (fun () -> Lwt_file_sink.emit sink event)
  (fun exn ->
    Log.error "Sink failed" [("error", `String (Printexc.to_string exn))];
    Lwt.return ())
```

## Architecture Notes

### Pattern Consistency
- Lwt and Eio packages share conceptual patterns but implement independently
- No shared code between Lwt and Eio packages - intentional separation
- Async_abstractions module was removed - was unused documentation-only stubs

### Sink Implementation Notes
- Lwt file sinks open channels lazily (on first write)
- Eager opening can cause resource leaks in long-running apps
- Different resource management approaches require separate implementations

### Lwt_sink.sink_fn Type Independence
- `Lwt_sink.sink_fn` is separate from `Composite_sink.sink_fn` in core library
- Changes to core sink types require corresponding changes here
- Per-sink min_level filtering: wrap emit_fn with level check at creation
- Lwt uses `Lwt.return ()` for skipped events, sync sinks use `()`

### Async Data Flow

```
Application (Lwt.t)
       |
       v
Level Check
       |
       v
Template Expansion (PPX)
       |
       v
Enqueue (optional)
       |
       v
Background Thread / Lwt
       |
       v
Circuit Breaker (optional)
       |
       v
Lwt Sinks
```

### Resource Management
```ocaml
(* Lazy channel opening *)
let get_channel t =
  match t.channel with
  | Some ch -> Lwt.return ch
  | None ->
    let* ch = open_channel t.path in
    t.channel <- Some ch;
    Lwt.return ch
```

## Testing Strategy

### Lwt Test Files
- `message-templates-lwt/test/test_lwt_logger.ml` - Logger functionality
- `message-templates-lwt/test/test_lwt_sinks.ml` - Sink operations

### Running Lwt Tests
```bash
dune exec message-templates-lwt/test/test_lwt_logger.exe
dune exec message-templates-lwt/test/test_lwt_sinks.exe
```

### Testing Patterns
```ocaml
let test_lwt_logger () =
  let* logger = create_test_logger () in
  let* () = Lwt_logger.information logger "Test" [] in
  let* () = Lwt_logger.close logger in
  check bool "logged" true !logged;
  Lwt.return ()

let () = Lwt_main.run (test_lwt_logger ())
```

## Security & Compliance

### Async Safety
- Never block the Lwt event loop
- Use `Lwt.catch` for exception handling
- Close resources properly in finally blocks

### Dependencies
- `lwt` >= 5.6
- `message-templates` (same version)

### License
- MIT License

## Agent Guardrails

### Files Never Automatically Modify
- `messageTemplates_lwt.ml` exports list
- Lwt-specific type definitions

### Required Reviews
- Changes to `Lwt_sink.sink_fn` type
- Changes to async resource management

### Lwt-Specific Patterns
- Always use `Lwt.return ()` not `()` for skipped events
- Lazy resource opening preferred over eager
- Use `Lwt.catch` for error handling, not exceptions

### Testing Checklist
- [ ] Lwt tests pass: `dune exec message-templates-lwt/test/test_lwt_logger.exe`
- [ ] No blocking calls in async paths
- [ ] Proper resource cleanup

## Extensibility Hooks

### Custom Lwt Sink
```ocaml
module My_lwt_sink = struct
  type t = { ... }
  let emit t event = Lwt.return () (* async operation *)
  let flush t = Lwt.return ()
  let close t = Lwt.return ()
end
```

### Lwt Configuration
```ocaml
let logger =
  Configuration.create ()
  |> Configuration.write_to_console ~colors:true ()
  |> Lwt_configuration.create_logger
```

### Error Recovery
```ocaml
let with_circuit_breaker cb logger =
  { logger with
    emit = (fun event ->
      match Circuit_breaker.call cb (fun () -> logger.emit event) with
      | Some result -> result
      | None -> Lwt.return ()) }
```

## Further Reading

- **../README.md** - Feature overview
- **../lib/AGENTS.md** - Core library architecture
- **../message-templates-eio/AGENTS.md** - Eio patterns (for comparison)
- **Lwt documentation** - https://github.com/ocsigen/lwt
