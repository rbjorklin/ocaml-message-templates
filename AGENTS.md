# AGENTS.md

## Project Overview

OCaml Message Templates - A PPX-based library for compile-time validated message templates with structured logging. Provides zero-runtime-overhead template processing with automatic variable capture from lexical scope.

## Architecture

```
Application Code
       |
       v
Level Check (fast path)
       |
       v
Template Expansion (PPX)
       |
       v
Context Enrichment (ambient properties)
       |
       v
Filtering (level/property-based)
       |
       v
Sinks (Console, File, etc.)
```

### Logger Emit Path
- Logger.write calls emit_fn directly on each sink - does NOT use Composite_sink.emit
- Composite_sink.emit is for external consumers, not internal Logger use
- Per-sink filtering must be implemented by wrapping emit_fn at sink creation time
- Architecture appears layered but Logger bypasses the composition layer for direct sink access

## Commands

Benchmark: "dune build @bench | tail -n 50"
Build: "dune build @install"
Test (Ocaml): "dune build @runtest" (NOTE: no output means all tests were successful)
Format code: "dune build --auto-promote @fmt"
Generate documentation: "dune build @doc"
Lint: "dune build @check"
Run single test executable: "dune exec test/test_ppx_comprehensive.exe"
Run example: "dune exec examples/logging_clef_ppx.exe"
Clean and rebuild: "dune clean && dune build @install"

```

## Code Style Guidelines

### Naming Conventions

- **Modules**: `CamelCase` (e.g., `Log_event`, `Console_sink`, `Template_parser`)
- **Types**: Define as `t` inside module, use qualified references (e.g., `Level.t`, `Log_event.t`)
- **Functions/variables**: `snake_case` (e.g., `parse_template`, `extract_holes`, `timestamp_expr`)
- **Constructors**: `CamelCase` (e.g., `Default`, `Structure`, `Stringify`, `Text`, `Hole`)
- **Module types**: `S` for signature, or descriptive name (e.g., `Sink.S`)

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

(* Use option types for nullable fields *)
alignment: (bool * int) option;
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

### Documentation

```ocaml
(** Module-level documentation with double asterisk *)

(** Function documentation
    @param param_name description
    @return description *)
let function_name param =
  ...

(** Type documentation *)
type t =
  | Variant  (* Case documentation *)
```

### Pattern Matching

```ocaml
(* Use exhaustive matching with explicit cases *)
match result with
| Ok parts -> process parts
| Error msg -> handle_error msg

(* For list operations, prefer pattern matching over List.* functions when clearer *)
let rec process = function
  | [] -> []
  | x :: xs -> f x :: process xs
```

### Error Handling

```ocaml
(* Use Result.t for operations that can fail *)
let parse_template str =
  match Angstrom.parse_string ~consume:All template str with
  | Ok parts -> Ok parts
  | Error msg -> Error msg

(* PPX errors: use Location.raise_errorf with descriptive messages *)
| Error msg -> Location.raise_errorf ~loc "MessageTemplates: Parse error: %s" msg

(* Option handling with explicit defaults *)
option Default (char '@' *> return Structure)
```

### Code Organization

- Keep modules focused (single responsibility)
- Module order: types first, then core functions, then helpers
- Group related functions with blank lines
- Maximum ~80-100 characters per line
- 2-space indentation

### Testing Style

```ocaml
(* Use Alcotest with descriptive test names *)
let test_level_ordering () =
  check bool "Verbose < Debug" true (Level.compare Level.Verbose Level.Debug < 0);
  check int "Debug = 1" 1 (Level.to_int Level.Debug)

let () =
  run "Level Tests" [
    "ordering", [
      test_case "Level ordering" `Quick test_level_ordering;
    ];
  ]
```

### PPX Code Generation

```ocaml
(* Use [%expr ...] for AST construction *)
let json_expr = [%expr `String [%e estring ~loc str]]

(* Use Ast_builder.Default functions for complex expressions *)
let tuple = pexp_tuple ~loc [expr1; expr2]
let apply = eapply ~loc func args

(* Include location in generated code *)
let loc = Expansion_context.Extension.extension_point_loc ctxt
```

## Project Structure

```
lib/           - Core library modules
ppx/           - PPX rewriter code
test/          - Test files (one per module)
examples/      - Usage examples
benchmarks/    - Performance benchmarks
```

## Key Patterns

- **Template expansion**: `[%template "User {name}"]` returns `(string * Yojson.Safe.t)`
- **Log levels**: Use Level.t with comparison operators (`>=`, `<`)
- **Sinks**: Implement `Sink.S` interface for custom outputs
- **Configuration**: Fluent builder pattern with `|>` operator
- **Context**: Use `Log_context.with_property` for ambient properties

## Common Tasks

- Adding new log level: Edit `lib/level.ml` and add variant
- Adding new sink: Create `lib/<name>_sink.ml` implementing `Sink.S`
- Adding new PPX extension: Edit `ppx/ppx_message_templates.ml`
- Template format specifiers: Edit `ppx/code_generator.ml`

## JSON Output Format

All log events follow CLEF (Compact Log Event Format):
```json
{
  "@t": "2026-01-31T23:54:42-00:00",
  "@mt": "User {username} logged in from {ip_address}",
  "@m": "User alice logged in from 192.168.1.1",
  "@l": "Information",
  "username": "alice",
  "ip_address": "192.168.1.1"
}
```

- `@t`: RFC3339 timestamp
- `@mt`: Message template (original template string with placeholders)
- `@m`: Rendered message (fully formatted with values)
- `@l`: Log level
- Additional fields: Captured variables and context properties

## Notes

- **Always run tests after changes have been applied**
- **Always format files after changes have been applied**
- **Always run examples after changes have been applied**
- **Always run benchmark after changes have been applied**
- **Template variables must be in scope**: PPX validates at compile time
- **Two output formats**: String for display, JSON for structured logging
- **Level checking is fast-path**: Minimal overhead when disabled
- **Log_context uses ambient state**: Properties flow across function calls
- **File sinks support rolling**: Daily, Hourly, Infinite, or By_size
- **Console sinks support colors**: Configurable with templates (ANSI codes)
- **Follows Message Templates spec**: https://messagetemplates.org/
- **When in plan mode you are allowed to write to**: .opencode/plans/

### String Parsing Normalization
- Level.of_string had 14 pattern match cases for different capitalizations ("Verbose", "verbose", "VRB", "vrb", etc.)
- Normalize once with `String.lowercase_ascii` then match on normalized form
- Reduced to 7 cases while maintaining same functionality
- Pattern applies to any string-to-variant parsing that needs case-insensitivity

### Comparison Operator Completeness
- Level module initially only exposed `(>=)` and `(<)` operators, missing `(>)`, `(<=)`, `(=)`, `(<>)`
- Users expect full comparison operator set for ordered types
- When adding comparison operators, include complete set: `compare`, `(=)`, `(<>)`, `(<)`, `(>)`, `(<=)`, `(>=)`
- Deriving `compare` from ppx_deriving can automate this, but manual implementation needed for fine-grained control
