# Project Overview

OCaml Message Templates is a PPX-based library for compile-time validated message templates with structured logging. It provides zero-runtime-overhead template processing with automatic variable capture from lexical scope, dual output (formatted strings and CLEF JSON), and a comprehensive logging infrastructure modeled after Serilog. The library targets OCaml 5.4.0+ and supports both synchronous and asynchronous (Lwt/Eio) logging patterns.

## Repository Structure

- **`lib/`** - Core library modules (loggers, sinks, filters, events, context)
- **`ppx/`** - PPX rewriter for compile-time template processing
- **`test/`** - Comprehensive test suite using Alcotest and QCheck
- **`examples/`** - Usage examples demonstrating features and patterns
- **`benchmarks/`** - Performance benchmarks using core_bench
- **`message-templates-lwt/`** - Lwt async concurrency support package
- **`message-templates-eio/`** - Eio effect-based concurrency support package
- **`doc/`** - Generated API documentation (odoc)
- **`logs/`** - Runtime log output directory
- **`.github/workflows/`** - CI/CD automation (documentation deployment)
- **`.opencode/`** - AI agent configuration and plans

## Build & Development Commands

```bash
# Install dependencies
opam install . --deps-only --with-test

# Build all packages
dune build @install

# Run tests (silent output = success)
dune build @runtest

# Run a specific test executable
dune exec test/test_ppx_comprehensive.exe

# Format code
dune build --auto-promote @fmt

# Lint and type-check
dune build @check

# Generate documentation
dune build @doc

# Run benchmarks
dune build --force @bench 2>&1 | tail -n 30

# Run examples
dune build --force @examples

# Clean and rebuild
dune clean && dune build @install

# Run a specific example
dune exec examples/basic.exe
dune exec examples/logging_ppx.exe
```

## Code Style & Conventions

### Naming
- **Modules**: `CamelCase` (e.g., `Log_event`, `Console_sink`, `Template_parser`)
- **Types**: Define as `t` inside module (e.g., `Level.t`, `Log_event.t`)
- **Functions/variables**: `snake_case` (e.g., `parse_template`, `timestamp_expr`)
- **Constructors**: `CamelCase` (e.g., `Default`, `Structure`, `Stringify`)
- **Module types**: `S` for signature (e.g., `Sink.S`)

### Formatting
- Use `dune fmt` with `.ocamlformat` configuration
- Line length: 80-100 characters
- Indentation: 2 spaces
- Profile: `ocamlformat` with sparse type declarations

### Documentation
```ocaml
(** Module-level documentation with double asterisk *)

(** Function documentation
    @param param_name description
    @return description *)
```

### Pattern Matching
- Use exhaustive matching with explicit cases
- Prefer pattern matching over chained `if/else` for ADTs

### Error Handling
- Use `Result.t` for fallible operations
- PPX errors: `Location.raise_errorf ~loc "MessageTemplates: %s" msg`

### Commit Message Template
```
<type>: <subject>

<body>

<footer>
```
Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

## Architecture Notes

### Data Flow

```
Application Code
       |
       v
Level Check (fast path)
       |
       v
Template Expansion (PPX at compile time)
       |
       v
Context Enrichment (ambient properties)
       |
       v
Filtering (level/property-based)
       |
       v
Sinks (Console, File, JSON, Composite, Null)
```

### Key Components

1. **Template Parser** (`template_parser.ml`) - Angstrom-based parser for message templates with holes, format specifiers, and alignment
2. **PPX Rewriter** (`ppx/`) - Compile-time code generation, validates variables against scope
3. **Log Event** (`log_event.ml`) - Core event type with timestamp, level, message template, rendered message, and properties
4. **Logger** (`logger.ml`) - Main logging interface, writes directly to sinks (bypasses Composite_sink internally)
5. **Sinks** - Output destinations: Console (colors), File (rolling), JSON (CLEF), Composite, Null
6. **Filters** (`filter.ml`) - Level-based and property-based event filtering
7. **Log Context** (`log_context.ml`) - Ambient property storage using Domain-local storage
8. **Configuration** (`configuration.ml`) - Fluent builder API for logger setup

### PPX vs Runtime Type Conversion
- **Critical constraint**: PPX expansion occurs BEFORE type checking, so compile-time type detection is impossible
- **Consequence**: Type annotations on variables (e.g., `let x : int = 42`) do NOT affect generated code - all template variables use `Runtime_helpers.generic_to_json`
- **Misconception to avoid**: The presence of type-specific converters (`string_to_json`, `int_to_json`, etc.) in `runtime_helpers.ml` does not mean the PPX uses them - it only uses `generic_to_json`

### Logger Emit Path
- `Logger.write` calls `emit_fn` directly on each sink
- Does NOT use `Composite_sink.emit` internally
- `Composite_sink.emit` is for external consumers
- Per-sink filtering implemented by wrapping `emit_fn` at sink creation time

## Testing Strategy

### Test Organization
- Unit tests: One test file per module (e.g., `test_level.ml`, `test_logger.ml`)
- Property-based tests: QCheck for parsers and filters (`test_qcheck_*.ml`)
- PPX tests: `test_ppx_comprehensive.ml`, `test_type_coverage.ml`
- Integration tests: Full logger lifecycle and sink interactions

### Running Tests
```bash
# All tests
dune build @runtest

# Specific test module
dune exec test/test_circuit_breaker.exe

# View test output
cat _build/_tests/latest/*.output
```

### Test Dependencies
- PPX must be built before tests using `[%template]` or `[%log.*]`
- Tests manually create `Composite_sink.sink_fn` records
- Changing `sink_fn` fields requires updating all test files

### CI
- GitHub Actions workflow in `.github/workflows/docs.yml`
- Deploys odoc to GitHub Pages on push to main
- Tests run via `dune build @runtest` in opam build

## Security & Compliance

### Secrets Handling
- No secrets in source code
- Use environment variables for configuration (see `CONFIGURATION.md` patterns)
- `.envrc` present for direnv support (user-managed)

### Dependencies
- Core: `ppxlib`, `angstrom`, `yojson`, `ptime`
- Test: `alcotest`, `qcheck`, `mdx`
- Dev: `core_bench`, `ppx_bench`
- All dependencies pinned in `dune-project` with minimum versions

### License
- MIT License (see `dune-project`)

### Compliance
- Implements [Message Templates specification](https://messagetemplates.org/)
- CLEF (Compact Log Event Format) output compatible with Serilog

## Agent Guardrails

### Files Never Automatically Modify
- `dune-project` version constraints (requires careful review)
- `*.opam` files (auto-generated from dune-project)
- `.ocamlformat` configuration
- Git history or tags

### Required Reviews
- Changes to PPX code generation (`ppx/code_generator.ml`)
- Changes to public API in `.mli` files
- New dependencies in `dune-project`
- Modifications to `Logger.t` type (affects `configuration.ml`)

### Rate Limits
- Run tests after every significant change
- Run format check before committing
- Run benchmarks when performance-critical code changes

### Safety Patterns
- Use `Fun.protect` with mutex operations to prevent deadlocks
- Never hold locks during I/O or user callbacks
- Check-Work-Record pattern for state machine operations

## Extensibility Hooks

### Custom Sinks
Implement `Sink.S` interface:
```ocaml
module My_sink : Sink.S = struct
  type t = { ... }
  let emit t event = ...
  let flush t = ...
  let close t = ...
end
```

### Environment Variables
- `LOG_LEVEL` - Configure minimum log level at runtime
- `LOG_FILE` - Configure log file path
- Standard OCaml vars (`OCAMLRUNPARAM`, etc.)

### Feature Flags
- `Timestamp_cache.set_enabled` - Toggle timestamp caching
- Per-sink `min_level` filtering
- Circuit breaker configuration (`failure_threshold`, `reset_timeout_ms`)

### Plugin Points
- Custom filters via `Filter.t` combinators
- Enrichers for adding ambient properties
- Output templates for sink formatting

## Further Reading

- **README.md** - Feature overview, usage examples, API reference
- **CONFIGURATION.md** - Complete configuration guide with patterns
- **DEPLOYMENT.md** - Production deployment guide
- **MIGRATION.md** - Migration guide between versions
- **lib/AGENTS.md** - Core library architecture details
- **ppx/AGENTS.md** - PPX implementation details
- **test/AGENTS.md** - Testing infrastructure notes
- **message-templates-lwt/AGENTS.md** - Lwt async patterns
- **message-templates-eio/AGENTS.md** - Eio async patterns
- `.opencode/plans/` - Active development plans
