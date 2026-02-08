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
