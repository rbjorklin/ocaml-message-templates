# Project Overview

Core library implementation for OCaml Message Templates. This directory contains the synchronous logging infrastructure, sink implementations, filters, and context management. It provides the foundational modules that async packages (Lwt/Eio) build upon.

## Repository Structure

- **`lib/`** - This directory: core library modules
  - `logger.ml` - Main logger interface and emit logic
  - `configuration.ml` - Fluent builder API for logger setup
  - `log_event.ml` - Log event type with timestamp, level, properties
  - `level.ml` - Six log levels with comparison operators
  - `*_sink.ml` - Sink implementations (Console, File, JSON, Null, Composite)
  - `filter.ml` - Level and property-based event filtering
  - `log_context.ml` - Ambient property storage using Domain.DLS
  - `circuit_breaker.ml` - Error recovery with state machine
  - `metrics.ml` - Per-sink performance tracking
  - `template_parser.ml` - Angstrom-based template parsing
  - `runtime_helpers.ml` - Type conversion and formatting utilities
  - `messageTemplates.ml` - Module exports

## Build & Development Commands

```bash
# Build just the core library
dune build lib/

# Run core library tests only
dune exec test/test_level.exe
dune exec test/test_logger.exe
dune exec test/test_sinks.exe
dune exec test/test_circuit_breaker.exe

# Type-check the library
dune build @check

# Generate docs for lib only
dune build @doc
```

## Code Style & Conventions

### Module Naming
- **Sinks**: `{destination}_sink.ml` (e.g., `console_sink.ml`, `file_sink.ml`)
- **Core types**: Define as `t` inside module (e.g., `Logger.t`, `Level.t`)
- **Module types**: Use `S` for signature (e.g., `Sink.S`)

### Type Definitions
```ocaml
(* Define core type as 't' inside module *)
type t =
  | Verbose
  | Debug
  | Information

(* Records with inline documentation *)
type hole = {
  name: string;
  operator: operator;
  format: string option;
}
```

### Imports and Opening Modules
```ocaml
(* At top of file, list opens *)
open Ppxlib
open Ast_builder.Default

(* For local module, open types explicitly *)
open Message_templates.Types
open Angstrom

(* Prefer qualified access for external modules *)
let json = Yojson.Safe.to_string data
let time = Ptime.to_rfc3339 timestamp
```

### Synchronization Patterns
Use `Fun.protect` with mutex operations:
```ocaml
let with_lock t f =
  Mutex.lock t.lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.lock) f
```

### Error Handling
Use `Result.t` for fallible operations:
```ocaml
let parse_template str =
  match Angstrom.parse_string ~consume:All template str with
  | Ok parts -> Ok parts
  | Error msg -> Error msg
```

## Architecture Notes

### Logger Type Architecture

```
┌─────────────────────────────────────────┐
│           Logger.t (abstract)           │
│  ┌─────────────┐  ┌──────────────────┐  │
│  │  min_level  │  │  filters: list   │  │
│  └─────────────┘  └──────────────────┘  │
│  ┌──────────────────────────────────┐   │
│  │  enrichers: (event -> event) list │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │  sinks: Composite_sink.sink_fn list│  │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

- `Logger.t` is abstract in interface but has concrete record type in implementation
- Internal fields (filters, enrichers, sinks) accessed directly in `configuration.ml`
- Adding new logger fields requires updating BOTH `logger.ml` AND `configuration.ml`
- Use `add_filter`, `with_enricher` functions rather than direct record updates

### Sink Type Consistency
- `Logger.create` expects `Composite_sink.sink_fn list` (not `Composite_sink.t`)
- Mismatch between `.mli` declaration and `.ml` implementation was hidden by type abstraction
- Always verify sink types match between interface and implementation

### Runtime Helpers Coupling
- `console_sink.ml` and `file_sink.ml` share template formatting logic
- Both depend on `Level.to_short_string` for level formatting
- `generic_to_string` and `generic_to_json` use Obj module for fallback
- PPX generates calls to these for unknown types at compile time

### OCaml Runtime Representation
Per [OCamlverse runtime docs](https://ocamlverse.net/content/runtime.html):
- 246: Lazy (unevaluated), 250: Forward (evaluated lazy)
- 247: Closure, 248: Object, 249: Infix
- 251: Abstract, 252: String, 253: Float
- 254: Flat float array, 255: Custom

### Domain-Local Storage for Multicore Caching
- Use `Domain.DLS.new_key (fun () -> initial_value)` for per-domain state
- Each domain calls the initializer function independently on first access
- No locks needed - domains don't share heap, naturally contention-free
- Fibers within a domain share the same DLS value

### Check-Work-Record Pattern
- Check state under lock → do work unlocked → record results locked
- Example: `Circuit_breaker.call` checks state, executes function outside lock, then records
- Use multiple `with_lock` calls with unlocked work between them
- Never hold locks during blocking operations (I/O, callbacks, user functions)

### Logger Emit Path
- `Logger.write` calls `emit_fn` directly on each sink
- Does NOT use `Composite_sink.emit` internally
- `Composite_sink.emit` is for external consumers, not internal Logger use
- Per-sink filtering implemented by wrapping `emit_fn` at sink creation time

## Testing Strategy

### Unit Test Files
- One test file per module: `test_level.ml`, `test_logger.ml`, `test_sinks.ml`
- `test_circuit_breaker.ml` - State machine and error recovery
- `test_configuration.ml` - Builder API validation
- `test_global_log.ml` - Global logger interface
- `test_metrics.ml` - Performance tracking
- `test_timestamp_cache.ml` - Time caching

### Property-Based Tests
- `test_qcheck_filters.ml` - Filter combinators
- `test_qcheck_properties.ml` - Event properties
- `test_qcheck_templates.ml` - Template parsing

### Sink Creation in Tests
- Tests manually create `Composite_sink.sink_fn` records to inject test doubles
- Any new required field in `sink_fn` breaks all tests creating them
- Fix pattern: Add `; min_level= None` (or appropriate value) to record

### Test Output Inspection
- Alcotest output files: `_build/_tests/latest/`
- Files named `<test_suite>.<index>.output`
- Use `cat _build/_tests/latest/*.output` to view failures

## Security & Compliance

### Secrets Handling
- No secrets in source code
- Use environment variables for configuration
- Runtime config via `Sys.getenv_opt`

### Dependencies
- Core: `yojson`, `ptime`, `unix`
- Parser: `angstrom`
- Type-safe: No unsafe operations in production paths

### License
- MIT License

## Agent Guardrails

### Files Never Automatically Modify
- `.mli` files without careful API review
- `messageTemplates.ml` exports list
- Existing module signatures

### Required Reviews
- Changes to `Logger.t` type definition
- Changes to `Composite_sink.sink_fn` record fields
- New public API functions
- Changes to `runtime_helpers.ml` (affects PPX code generation)

### Module Registration Checklist
1. Create `.ml` and `.mli` files in `lib/`
2. Add module name to `lib/messageTemplates.ml` exports
3. Build with `dune build @install` to register with LSP
4. LSP "Unbound module" errors are normal before first build

## Extensibility Hooks

### Custom Sink Implementation
```ocaml
module My_sink : Sink.S = struct
  type t = { ... }
  let emit t event = ...
  let flush t = ...
  let close t = ...
end
```

### Sink Registration via Configuration
```ocaml
let my_sink =
  { Composite_sink.emit_fn = (fun e -> My_sink.emit t e)
  ; flush_fn = (fun () -> My_sink.flush t)
  ; close_fn = (fun () -> My_sink.close t)
  ; min_level = Some Level.Information }
in
Configuration.create ()
|> Configuration.write_to my_sink
|> Configuration.build
```

### Filter Combinators
```ocaml
Filter.all [
  Filter.level_filter Level.Warning;
  Filter.property_filter "component" (function
    | `String "auth" -> true
    | _ -> false)
]
```

### Environment-Based Configuration
```ocaml
let level =
  match Sys.getenv_opt "LOG_LEVEL" with
  | Some "debug" -> Level.Debug
  | _ -> Level.Information
```

## Further Reading

- **../README.md** - Feature overview and usage examples
- **../CONFIGURATION.md** - Complete configuration guide
- **../ppx/AGENTS.md** - PPX implementation details
- **../test/AGENTS.md** - Testing infrastructure
- **../message-templates-lwt/AGENTS.md** - Lwt async patterns
- **../message-templates-eio/AGENTS.md** - Eio async patterns
