# AGENTS.md

## Logger Type Architecture

### Type Abstraction Constraint
- `Logger.t` is abstract in interface but has concrete record type in implementation
- Internal fields (filters, enrichers, sinks) accessed directly in `configuration.ml`
- Adding new logger fields requires updating BOTH `logger.ml` AND `configuration.ml`
- Use `add_filter`, `with_enricher` functions rather than direct record updates

### Sink Type Consistency
- `Logger.create` expects `Composite_sink.sink_fn list` (not `Composite_sink.t`)
- Mismatch between `.mli` declaration and `.ml` implementation was hidden by type abstraction
- Always verify sink types match between interface and implementation

## Runtime Helpers Coupling

### Shared Formatting Dependencies
- `console_sink.ml` and `file_sink.ml` share template formatting logic
- Both depend on `Level.to_short_string` for level formatting
- Extracting common code to `runtime_helpers.ml` requires keeping Level dependency

### Type Conversion Strategy
- `generic_to_string` and `generic_to_json` required despite Obj module usage
- PPX generates calls to these for unknown types at compile time
- Cannot fully remove Obj usage without breaking template fallback for complex types

## OCaml Runtime Representation

### Obj Tag Values (246-255)
Per [OCamlverse runtime docs](https://ocamlverse.net/content/runtime.html):
- 246: Lazy (unevaluated), 250: Forward (evaluated lazy - dereference field 0)
- 247: Closure, 248: Object, 249: Infix
- 251: Abstract (not scanned by GC)
- 252: String, 253: Float, 254: Flat float array, 255: Custom

### Set/Map Internal Structure
- Set.Make: AVL tree with 4 fields (left, value, right, height)
- Map.Make: AVL tree with 5 fields (left, key, data, right, height)
- Empty nodes represented as integer 0 (tag check in try_traverse_set_tree)
- Detection heuristic: block with tag 0 and size 4 or 5

### List Representation
- Empty list `[]` is integer 0 (same as Empty constructor)
- Non-empty list is block with tag 0, size 2 (head, tail)
- Must check size=2 to distinguish from tuple/record with tag 0

### Block Output Format
- Tag 0 blocks with fields shown as `(field1, field2, ...)`
- Empty blocks shown as `()`
- Non-zero tag blocks shown as `<tag:N|field1; field2>` (before stripping)

## Synchronization Patterns

### Mutex Safety with Fun.protect
- Manual `Mutex.lock`/`Mutex.unlock` pairs are error-prone and can deadlock on exceptions
- Use `with_lock t f = Mutex.lock t.lock; Fun.protect ~finally:(fun () -> Mutex.unlock t.lock) f`
- Pattern used in circuit_breaker.ml and other modules with mutex-protected state
- Exceptions no longer escape with locks held, preventing deadlock scenarios

### Check-Work-Record Pattern
- Some operations need to: check state under lock → do work unlocked → record results locked
- Example: `Circuit_breaker.call` checks state, executes function outside lock, then records success/failure
- Use multiple `with_lock` calls with the unlocked work happening between them
- Never hold locks during potentially blocking operations (I/O, callbacks, user functions)

## Module Interface Hygiene

### Missing .mli File Detection
- 9 modules lacked .mli files: composite_sink, filter, json_sink, level, log_context, log, null_sink, template_parser, types
- Missing interfaces expose implementation details and prevent API change tracking
- Adding .mli files requires careful review of exported types and functions
- Always verify public API surface area after adding interface files

## Code Duplication Patterns

### Date/Time Extraction in File Sink
- `should_roll` function duplicated Unix.gmtime conversion logic for Daily/Hourly checks
- Extract `to_date_tuple` and `to_hour_tuple` helpers to eliminate duplication
- Prevents inconsistencies if rolling logic changes in one place but not another

### State Machine Logic Duplication
- Circuit breaker had identical state transition logic in both `get_state` and `call` functions
- Extract `try_transition_to_half_open` helper for single source of truth
- State transitions must be atomic and consistent across all entry points

## Configuration Builder Patterns

### Sink Creation Boilerplate
- File, console, and null sinks had nearly identical creation patterns in configuration.ml
- Generic `add_sink` helper with labeled arguments eliminates ~40% boilerplate
- All sinks follow same pattern: create -> wrap in sink_fn -> add to config.sinks
- Extract early to prevent drift between sink type implementations

### Per-Sink Level Filtering Implementation
- Per-sink min_level filtering happens at sink creation time, NOT in Composite_sink.emit
- Logger.write calls emit_fn directly on each sink, bypassing Composite_sink entirely
- Must wrap emit_fn with level checking during sink creation in configuration.ml
- Runtime check: `event_level >= sink_min_level`, skip if false

### Sink Type Changes Cascade
- Adding fields to `Composite_sink.sink_fn` requires updates in:
  - test/test_sinks.ml, test/test_logger.ml (manual sink_fn creation)
  - examples/*.ml (manual sink creation in CLEF examples)
  - benchmarks/benchmark.ml (composite_sink_emit test)
  - Both Lwt and Eio packages have their own sink_fn types

## Domain-Local Storage for Multicore Caching

### Domain.DLS Pattern
- Use `Domain.DLS.new_key (fun () -> initial_value)` for per-domain state
- Each domain calls the initializer function independently on first access
- No locks needed - domains don't share heap, naturally contention-free
- Fibers within a domain share the same DLS value

### Atomic Global Flags
- Use `Atomic.make true` for runtime-configurable global settings
- `Atomic.set`/`Atomic.get` provide thread-safe access without mutex overhead
- Pattern used for `Timestamp_cache.set_enabled` to disable caching globally

## Module Registration Requirements

### New Module Checklist
- Create `.ml` and `.mli` files in `lib/`
- Add module name to `lib/messageTemplates.ml` exports
- Build with `dune build @install` to register with LSP
- LSP "Unbound module" errors are normal before first build

## Time Caching Granularity

### Millisecond Truncation Strategy
- Truncate to milliseconds first: `Int64.of_float (Unix.gettimeofday () *. 1000.0)`
- Then convert back to float seconds for `Ptime.of_float_s`
- Ensures all timestamps within same millisecond have identical Ptime.t values
- RFC3339 formatting with `~frac_s:3` preserves millisecond precision
