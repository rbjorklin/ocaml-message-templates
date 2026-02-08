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
