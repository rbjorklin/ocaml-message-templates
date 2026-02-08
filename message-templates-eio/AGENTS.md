# Project Overview

Eio effect-based concurrency support for OCaml Message Templates. This package provides structured concurrency logging using OCaml 5.4+ effect handlers. Eio offers direct-style async with fiber-based parallelism and clear resource lifetimes.

## Repository Structure

- **`message-templates-eio/`** - This directory: Eio async package
  - `lib/` - Eio-specific implementations
    - `eio_logger.ml` - Eio logger interface
    - `eio_configuration.ml` - Eio configuration builder
    - `eio_file_sink.ml` - Eio file operations
    - `eio_console_sink.ml` - Eio console output
    - `eio_sink.ml` - Eio sink type definitions
    - `messageTemplates_eio.ml` - Module exports
  - `examples/` - Eio usage examples
  - `test/` - Eio-specific tests

## Build & Development Commands

```bash
# Build Eio package
dune build message-templates-eio/

# Install dependencies
opam install eio eio_main

# Run Eio tests
dune exec message-templates-eio/test/test_eio_logger.exe

# Run Eio examples
dune exec message-templates-eio/examples/eio_example.exe

# Build all packages including Eio
dune build @install
```

## Code Style & Conventions

### Eio Naming
- Prefix modules with `eio_` (e.g., `eio_logger.ml`, `eio_file_sink.ml`)
- Use direct-style (no Lwt.t wrapper)
- Accept switch parameter for fiber management

### Structured Concurrency
```ocaml
Eio.Switch.run @@ fun sw ->
let logger = Eio_configuration.create_logger ~sw config in
(* logger bound to switch lifetime *)
Eio_logger.information logger "Message" [];
(* cleanup happens automatically when switch exits *)
```

### Resource Management
```ocaml
(* Eio file sinks open channels eagerly on creation *)
let create ~sw path =
  let fd = Eio.Path.open_out ~sw path ~create:(`If_missing 0o644) in
  { path; fd }
```

## Architecture Notes

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

### Async Data Flow

```
Application (Eio fiber)
       |
       v
Level Check
       |
       v
Template Expansion (PPX)
       |
       v
Spawn Fiber (optional)
       |
       v
Circuit Breaker (optional)
       |
       v
Eio Sinks
```

### Switch-Based Lifetimes
```ocaml
Eio.Switch.run @@ fun sw ->
(* All resources created with ~sw are cleaned up when switch exits *)
let logger = create_logger ~sw config in
Eio_logger.information logger "Hello" [];
(* implicit cleanup *)
```

## Testing Strategy

### Eio Test Files
- `message-templates-eio/test/test_eio_logger.ml` - Logger functionality
- `message-templates-eio/test/test_eio_sinks.ml` - Sink operations

### Running Eio Tests
```bash
dune exec message-templates-eio/test/test_eio_logger.exe
dune exec message-templates-eio/test/test_eio_sinks.exe
```

### Testing Patterns
```ocaml
let test_eio_logger () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let logger = create_test_logger ~sw env in
  Eio_logger.information logger "Test" [];
  check bool "logged" true !logged
```

## Security & Compliance

### Effect Handler Safety
- Never escape switch context
- Use `Fun.protect` for cleanup
- Handle cancellation properly

### Dependencies
- `eio` >= 1.0
- `eio_main` >= 1.0
- `message-templates` (same version)
- Requires OCaml 5.4.0+

### License
- MIT License

## Agent Guardrails

### Files Never Automatically Modify
- `messageTemplates_eio.ml` exports list
- Eio-specific type definitions
- Effect handler usage patterns

### Required Reviews
- Changes to `Eio_sink.sink_fn` type
- Changes to switch lifetime management
- Effect handler patterns

### Eio-Specific Patterns
- Always pass `~sw` parameter for resource creation
- Eager resource opening (not lazy like Lwt)
- Direct-style return types (no Lwt.t)
- Use `Eio.Fiber` for concurrent operations

### Testing Checklist
- [ ] Eio tests pass: `dune exec message-templates-eio/test/test_eio_logger.exe`
- [ ] Proper switch usage in all resource creation
- [ ] Handles cancellation correctly

## Extensibility Hooks

### Custom Eio Sink
```ocaml
module My_eio_sink = struct
  type t = { fd : Eio.File.w Eio.Flow.sink; ... }
  let emit t event = Eio.Flow.write_string t.fd (format_event event)
  let flush t = ()
  let close t = Eio.Flow.close t.fd
end
```

### Eio Configuration
```ocaml
let run ~stdout ~fs =
  Eio.Switch.run @@ fun sw ->
  let logger =
    Configuration.create ()
    |> Configuration.write_to_console ~colors:true ()
    |> Eio_configuration.create_logger ~sw
  in
  Eio_logger.information logger "Hello" [];
  Eio_logger.close logger
```

### Fire-and-Forget Logging
```ocaml
(* Spawn fiber for background logging *)
let write_async logger msg properties =
  Eio.Fiber.fork ~sw (fun () ->
    Eio_logger.write logger msg properties)
```

## Further Reading

- **../README.md** - Feature overview
- **../lib/AGENTS.md** - Core library architecture
- **../message-templates-lwt/AGENTS.md** - Lwt patterns (for comparison)
- **Eio documentation** - https://github.com/ocaml-multicore/eio
