# Project Overview

Comprehensive test suite for OCaml Message Templates. Tests cover unit tests, property-based tests (QCheck), PPX integration tests, and async package tests. All tests use Alcotest framework with silent output on success.

## Repository Structure

- **`test/`** - This directory: test files
  - `test_level.ml` - Log level ordering and conversions
  - `test_logger.ml` - Logger interface and emit path
  - `test_sinks.ml` - Sink implementations (Console, File, JSON, Null)
  - `test_configuration.ml` - Configuration builder API
  - `test_global_log.ml` - Global logger interface
  - `test_circuit_breaker.ml` - Error recovery state machine
  - `test_metrics.ml` - Performance tracking
  - `test_timestamp_cache.ml` - Time caching
  - `test_log_context.ml` - Ambient context
  - `test_filter.ml` - Event filtering
  - `test_parser.ml` - Template parsing
  - `test_escape.ml` - Template escaping
  - `test_ppx_comprehensive.ml` - PPX functionality
  - `test_type_coverage.ml` - Type conversion coverage
  - `test_qcheck_*.ml` - Property-based tests
  - `test_shutdown.ml` - Graceful shutdown
  - `ppx/` - PPX-specific test utilities

## Build & Development Commands

```bash
# Run all tests
dune build @runtest

# Run specific test executable
dune exec test/test_level.exe
dune exec test/test_logger.exe
dune exec test/test_sinks.exe
dune exec test/test_ppx_comprehensive.exe

# Run all property-based tests
dune exec test/test_qcheck_filters.exe
dune exec test/test_qcheck_properties.exe
dune exec test/test_qcheck_templates.exe

# View test output
cat _build/_tests/latest/*.output

# View specific test output
cat _build/_tests/latest/Level_Tests.000.output
```

## Code Style & Conventions

### Test Naming
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

### Adding Debug Output
```ocaml
(* Use Printf.printf with %! to flush during test runs *)
Printf.printf "Debug: value = %d\n%" value;
(* Output appears in test output files, not stdout *)
```

### Sink Record Creation in Tests
```ocaml
(* Tests manually create Composite_sink.sink_fn records *)
let test_sink =
  { Composite_sink.emit_fn = (fun e -> ...)
  ; flush_fn = (fun () -> ())
  ; close_fn = (fun () -> ())
  ; min_level = None }
```

## Architecture Notes

### Dune Test Registration
- `test/dune` lists all test executables explicitly in `(names ...)` field
- Removing a test module requires updating `test/dune` or build fails
- No automatic discovery - must manually sync test files with dune configuration

### Test Output Locations
- Alcotest output files: `_build/_tests/latest/` or `_build/default/test/_build/_tests/<TestName>/`
- Files named `<test_suite>.<index>.output` (e.g., `uncovered_types.004.output`)
- Use `cat _build/_tests/latest/*.output` to see recent test results

### Baseline Test Strategy
```bash
# When tests fail after changes, use git stash to test without your changes
git stash
dune build @runtest

# If failures exist on baseline, your changes didn't cause them
git stash pop
```

### Circuit Breaker Test Coupling
- `test_circuit_breaker.ml` accesses stats as record fields (`s1.failure_count`)
- Changing stats type from record to tuple broke tests
- Stats type changes require updating both implementation AND test assertions

### PPX Test Dependencies
- PPX tests (`test_ppx_*.ml`) generate code referencing Runtime_helpers
- Changing Runtime_helpers function names breaks PPX tests even if core tests pass
- Must update BOTH `ppx/code_generator.ml` AND test assertions together

### Sink Type Changes Cascade
Adding fields to `Composite_sink.sink_fn` requires updates in:
- `test/test_sinks.ml`, `test/test_logger.ml` (manual sink_fn creation)
- `examples/*.ml` (manual sink creation in CLEF examples)
- `benchmarks/benchmark.ml` (composite_sink_emit test)
- Both Lwt and Eio packages have their own sink_fn types

## Testing Strategy

### Unit Tests
One test file per module:
- `test_level.ml` - Level ordering, conversions, operators
- `test_logger.ml` - Logger creation, writing, filtering
- `test_sinks.ml` - All sink types (Console, File, JSON, Null, Composite)
- `test_configuration.ml` - Builder API patterns
- `test_global_log.ml` - Global logger set/get
- `test_circuit_breaker.ml` - State machine transitions
- `test_metrics.ml` - Event counting, latency tracking
- `test_timestamp_cache.ml` - Time caching behavior
- `test_log_context.ml` - Context property propagation
- `test_filter.ml` - Filter combinators
- `test_parser.ml` - Template parsing edge cases
- `test_escape.ml` - Brace escaping

### Property-Based Tests (QCheck)
- `test_qcheck_filters.ml` - Filter properties
- `test_qcheck_properties.ml` - Event property invariants
- `test_qcheck_templates.ml` - Template parsing properties

### PPX Integration Tests
- `test_ppx_comprehensive.ml` - All PPX features
- `test_type_coverage.ml` - Type conversion coverage

### Type Annotation Tests
- Explicit type annotations in tests (e.g., `let x : int = 42`) are for documentation clarity only
- PPX cannot use type annotations because it runs before type checking
- All type conversion tests verify runtime behavior of `generic_to_json`, not compile-time code generation
- When adding type-specific tests, remember they test the Obj-based runtime converter, not type-specific converters

### Async Package Tests
- `message-templates-lwt/test/` - Lwt-specific tests
- `message-templates-eio/test/` - Eio-specific tests

## Security & Compliance

### Test Data
- No real secrets in test data
- Use mock/test doubles for external dependencies
- Property-based tests use generated data

### Dependencies
- `alcotest` - Test framework
- `qcheck` - Property-based testing
- `mdx` - Documentation tests

## Agent Guardrails

### Files Never Automatically Modify
- `test/dune` test registration list
- Existing test assertions without verification

### Required Reviews
- New test files need dune registration
- Changes to test assertions when underlying types change
- Changes to sink record creation patterns

### Adding New Tests
1. Create `test/test_<module>.ml`
2. Add name to `test/dune` `(names ...)` field
3. Follow existing test naming convention
4. Run `dune exec test/test_<module>.exe` to verify

### Test Failure Investigation
1. Run `cat _build/_tests/latest/*.output` to see failures
2. Use `git stash` to check if failures are pre-existing
3. Examine output before assuming your changes broke the test
4. Add debug prints with `Printf.printf "...\n%!"` if needed

### Pre-Commit Checklist
- [ ] All tests pass: `dune build @runtest`
- [ ] Specific test runs: `dune exec test/test_<changed_module>.exe`
- [ ] No debug prints left in code

## Extensibility Hooks

### Adding Unit Tests
```ocaml
let test_my_feature () =
  let result = MyModule.my_function input in
  check int "expected value" 42 result

let () =
  run "MyModule Tests" [
    "feature", [test_case "my feature" `Quick test_my_feature];
  ]
```

### Adding Property-Based Tests
```ocaml
let test_property =
  Test.make ~name:"my property" my_generator (fun value ->
    let result = MyModule.process value in
    check_result result)

let () = QCheck_runner.run_tests_main [test_property]
```

### Test Doubles Pattern
```ocaml
(* Create fake sink for testing *)
let create_test_sink () =
  let events = ref [] in
  let sink =
    { Composite_sink.emit_fn = (fun e -> events := e :: !events)
    ; flush_fn = (fun () -> ())
    ; close_fn = (fun () -> ())
    ; min_level = None }
  in
  (sink, events)
```

## Further Reading

- **../README.md** - Feature overview
- **../lib/AGENTS.md** - Core library architecture
- **../ppx/AGENTS.md** - PPX implementation
- **Alcotest documentation** - https://github.com/mirage/alcotest
- **QCheck documentation** - https://github.com/c-cube/qcheck
