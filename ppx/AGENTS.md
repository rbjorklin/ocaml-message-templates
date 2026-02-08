# AGENTS.md

## PPX Implementation Details

### Code Generation Dependencies
- PPX in `code_generator.ml` generates references to `Message_templates.Runtime_helpers` functions
- When modifying Runtime_helpers function names, must update BOTH `lib/runtime_helpers.ml` AND `ppx/code_generator.ml`
- Generic type conversion (`generic_to_string`, `generic_to_json`) uses Obj module - required for fallback when compile-time type info unavailable

### Type Conversion Fallback Chain
1. PPX tries compile-time type detection first (int, string, float, etc.)
2. Falls back to Runtime_helpers.generic_to_json for unknown types
3. Obj module runtime inspection used only as last resort

### Build Dependencies
- PPX must be built before test files that use `[%template]` or `[%log.*]` extensions
- `dune build @install` builds PPX first, then tests
- Test failures in PPX tests usually indicate code generation issues, not runtime bugs
