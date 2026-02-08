# AGENTS.md

## Test Infrastructure

### Dune Test Registration
- `test/dune` lists all test executables explicitly in `(names ...)` field
- Removing a test module requires updating `test/dune` or build fails with "Module doesn't exist"
- No automatic discovery - must manually sync test files with dune configuration

### Circuit Breaker Test Coupling
- `test_circuit_breaker.ml` accesses stats as record fields (`s1.failure_count`)
- Changing stats type from record to tuple broke tests
- Stats type changes require updating both implementation AND test assertions

### PPX Test Dependencies
- PPX tests (`test_ppx_*.ml`) generate code referencing Runtime_helpers
- Changing Runtime_helpers function names breaks PPX tests even if core tests pass
- Must update BOTH `ppx/code_generator.ml` AND test assertions together

## Debugging Test Output

### Test Output Locations
- Alcotest output files: `_build/_tests/latest/` or `_build/default/test/_build/_tests/<TestName>/`
- Files named `<test_suite>.<index>.output` (e.g., `uncovered_types.004.output`)
- Use `cat _build/_tests/latest/*.output` to see recent test results

### Adding Debug Output to Tests
- Use `Printf.printf "%s%!" msg` (with `%!` to flush) to see values during test runs
- Output appears in test output files, not stdout
- Remove debug prints before committing

## Identifying Pre-Existing Failures

### Baseline Test Strategy
- When tests fail after changes, use `git stash` to test without your changes
- Run `dune build @runtest` on clean baseline to identify pre-existing failures
- If failures exist on baseline, your changes didn't cause them
- Restore changes with `git stash pop` after verification

### Test Output Inspection
- Failed test output saved to `_build/_tests/latest/<TestName>/`
- Files named `<suite>.<index>.output` contain assertion failure details
- Use `cat _build/_tests/latest/*.output` to view all recent failures
- Examine output before assuming your changes broke the test
