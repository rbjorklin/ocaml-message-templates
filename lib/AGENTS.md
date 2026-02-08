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
