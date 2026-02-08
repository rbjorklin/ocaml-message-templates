# Project Overview

PPX rewriter implementation for OCaml Message Templates. This directory contains the compile-time code generation that transforms `[%template]` and `[%log.*]` extensions into efficient OCaml code. The PPX validates templates against lexical scope and generates zero-runtime-overhead string and JSON output.

## Repository Structure

- **`ppx/`** - This directory: PPX rewriter code
  - `ppx_message_templates.ml` - Main PPX entry point and extension registration
  - `code_generator.ml` - OCaml AST generation for templates
  - `dune` - Build configuration

## Build & Development Commands

```bash
# Build PPX (must be done before running tests that use it)
dune build ppx/

# Build and install all packages (builds PPX first)
dune build @install

# Run PPX-specific tests
dune exec test/test_ppx_comprehensive.exe
dune exec test/test_type_coverage.exe

# Debug PPX output (see generated code)
dune exec examples/basic.exe

# Clean and rebuild (needed after PPX changes)
dune clean && dune build @install
```

## Code Style & Conventions

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

### Error Handling
```ocaml
(* PPX errors: use Location.raise_errorf with descriptive messages *)
| Error msg -> Location.raise_errorf ~loc "MessageTemplates: Parse error: %s" msg
```

### Pattern Matching
```ocaml
(* Use exhaustive matching with explicit cases *)
match result with
| Ok parts -> process parts
| Error msg -> handle_error msg
```

## Architecture Notes

### Code Generation Pipeline

```
Source Code with [%template]
            |
            v
    Template Parsing (Angstrom)
            |
            v
    Variable Scope Validation
            |
            v
    AST Generation (code_generator.ml)
            |
            v
    OCaml Code with Runtime Type Conversion
```

**Note:** Type detection at compile time is not possible because PPX expansion
occurs before type checking. All template variables use runtime type conversion
via `Runtime_helpers.generic_to_json`.

### Code Generation Dependencies
- PPX in `code_generator.ml` generates references to `Message_templates.Runtime_helpers` functions
- When modifying Runtime_helpers function names, must update BOTH `lib/runtime_helpers.ml` AND `ppx/code_generator.ml`
- All template variables use `generic_to_string`/`generic_to_json` with Obj module for runtime type introspection

### Type Conversion (Simplified)

PPX expansion occurs before type checking, so compile-time type detection is not
possible. All template variables use `Runtime_helpers.generic_to_json` for JSON
conversion, which performs runtime type introspection using the Obj module.

1. PPX cannot determine types at compile time (runs before type checker)
2. All variables use `generic_to_json` which inspects values at runtime
3. Obj module is used for runtime type introspection

### Stringify Operator Code Path
- `{$var}` generates call to `Runtime_helpers.generic_to_string` (not `generic_to_json`)
- Stringify ALWAYS uses Obj fallback since it's for display, not JSON
- Note: Explicit type annotations cannot avoid Obj overhead because PPX runs before type checking

### Build Dependencies
- PPX must be built before test files that use `[%template]` or `[%log.*]` extensions
- `dune build @install` builds PPX first, then tests
- Test failures in PPX tests usually indicate code generation issues, not runtime bugs

## Testing Strategy

### PPX Test Files
- `test/test_ppx_comprehensive.ml` - Core PPX functionality
- `test/test_type_coverage.ml` - Type conversion coverage
- `test/test_escape.ml` - Template escaping
- `test/test_parser.ml` - Template parsing

### Test Dependencies
- PPX tests generate code referencing Runtime_helpers
- Changing Runtime_helpers function names breaks PPX tests even if core tests pass
- Must update BOTH `ppx/code_generator.ml` AND test assertions together

### Build Order
```
1. lib/ (core library)
2. ppx/ (this directory)
3. test/ (tests using PPX extensions)
4. examples/ (examples using PPX)
```

### Debugging Generated Code
Add explicit type annotations and run examples:
```ocaml
let msg, json = [%template "Count: {count}"] in
Printf.printf "%s\n" msg
```

## Security & Compliance

### Code Generation Safety
- Generated code uses only public APIs
- No unsafe code generation (no Obj.magic in generated code)
- All type conversions go through Runtime_helpers

### Dependencies
- `ppxlib` - PPX framework
- `angstrom` - Template parsing (shared with runtime)

### License
- MIT License

## Agent Guardrails

### Files Never Automatically Modify
- `ppx_message_templates.ml` extension registration points
- AST construction patterns without verification

### Required Reviews
- Changes to `code_generator.ml` - affects all generated code
- Changes to type detection logic
- Changes to variable scope validation
- New extension points

### PPX Change Checklist
1. Update `ppx/code_generator.ml` if generating new code patterns
2. Update `lib/runtime_helpers.ml` if new runtime support needed
3. Run `dune clean && dune build @install` to rebuild everything
4. Run PPX tests: `dune exec test/test_ppx_comprehensive.exe`
5. Run examples: `dune build --force @examples`

### Breaking Changes
- Changing generated code structure affects all users
- Changes to Runtime_helpers function names are breaking
- Maintain backwards compatibility or bump major version

## Extensibility Hooks

### Adding New Extensions
Edit `ppx_message_templates.ml`:
```ocaml
let my_extension =
  Extension.declare
    "my.extension"
    Extension.Context.expression
    Ast_pattern.(...)
    expand_function
```

### Custom Format Specifiers
Edit `code_generator.ml` format handling:
```ocaml
match format with
| Some ":x" -> generate_hex_format expr
| _ -> default_format expr
```

### Type Detection Extension

**Note:** Type detection at PPX time is not currently implemented because PPX
expansion occurs before type checking. The `ty` parameter in `yojson_of_value`
is always `None`.

If compile-time type detection is desired, it would require:
1. New syntax for explicit type annotations in templates (e.g., `{(var : int)}`)
2. Parser support for the new syntax
3. Updated code generation to use type-specific converters

For now, all type conversion is done at runtime via `generic_to_json`.

## Further Reading

- **../README.md** - Feature overview and template syntax
- **../lib/AGENTS.md** - Core library architecture
- **../lib/runtime_helpers.ml** - Type conversion utilities
- **../test/AGENTS.md** - Testing infrastructure
