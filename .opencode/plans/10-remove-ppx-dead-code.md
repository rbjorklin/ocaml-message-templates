# Plan 10: Remove Dead Code from PPX Code Generator

## Status
**Priority:** MEDIUM  
**Estimated Effort:** 2-3 hours  
**Risk Level:** Low (code cleanup, no behavioral changes)
**Dependencies:** None (can proceed independently)

## Problem Statement

The PPX code generator (`ppx/code_generator.ml`) contains type-specific conversion logic that is never executed because the scope analyzer cannot extract type information during PPX expansion.

### Current Dead Code

In `ppx/code_generator.ml`, the `yojson_of_value` function (lines 25-67) has type-specific branches for:

```ocaml
let rec yojson_of_value ~loc (expr : expression) (ty : core_type option) =
  match ty with
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "string"; _}, []); _} ->
      [%expr `String [%e expr]]  (* DEAD CODE - ty is always None *)
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "int"; _}, []); _} ->
      [%expr `Int [%e expr]]     (* DEAD CODE - ty is always None *)
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "float"; _}, []); _} ->
      [%expr `Float [%e expr]]   (* DEAD CODE - ty is always None *)
  (* ... 10+ more Some cases that are never reached ... *)
  | _ ->
      (* This is the ONLY reachable case *)
      [%expr Message_templates.Runtime_helpers.generic_to_json [%e expr]]
```

### Why Type Info Is Unavailable

The scope analyzer (`ppx/scope_analyzer.ml`, lines 99-106) explicitly does not extract type information:

```ocaml
let scope_from_let_bindings vbs =
  List.fold_left
    (fun scope vb ->
      let names = extract_pattern_names vb.pvb_pat in
      (* Type information not available at PPX stage, so we store None *)
      List.fold_left (fun sc name -> add_binding name None sc) scope names )
    empty_scope vbs
```

The comment confirms: **"Type information not available at PPX stage"**

This is a fundamental limitation - PPX runs before type checking, so variable types haven't been determined yet.

### Impact of Dead Code

1. **Maintenance burden**: 40+ lines of unreachable code to maintain
2. **False expectations**: Suggests type-specific optimization that doesn't exist
3. **Confusion**: Developers may think type annotations help (they don't)
4. **Documentation drift**: Comments suggest compile-time type detection works

## Solution

Remove the dead code and simplify the code generator to reflect actual behavior. Do NOT attempt to make type detection work (that's a separate, complex effort requiring compiler hooks or different PPX architecture).

### Rationale

- **Keep `generic_to_json`**: It provides valuable functionality for logging arbitrary values
- **Remove unreachable branches**: They create false expectations and maintenance overhead
- **Simplify code path**: Single clear code path is easier to understand and test
- **Preserve behavior**: No functional changes, only code cleanup

## Implementation Steps

### Step 1: Simplify `yojson_of_value` Function

**File:** `ppx/code_generator.ml`

**Before (40+ lines with dead branches):**
```ocaml
let rec yojson_of_value ~loc (expr : expression) (ty : core_type option) =
  match ty with
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "string"; _}, []); _} ->
      [%expr `String [%e expr]]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "int"; _}, []); _} ->
      [%expr `Int [%e expr]]
  (* ... 12 more Some cases ... *)
  | _ ->
      [%expr Message_templates.Runtime_helpers.generic_to_json [%e expr]]
```

**After (5 lines, single code path):**
```ocaml
let yojson_of_value ~loc (expr : expression) (_ty : core_type option) =
  (* Type information is not available at PPX expansion time,
     so we always use the generic runtime conversion.
     See scope_analyzer.ml for details on why types aren't extracted. *)
  [%expr Message_templates.Runtime_helpers.generic_to_json [%e expr]]
```

### Step 2: Update `apply_operator` Function

**File:** `ppx/code_generator.ml`

**Before:**
```ocaml
let apply_operator ~loc op expr ty =
  match op with
  | Default -> yojson_of_value ~loc expr ty
  (* ... *)
```

**After:**
```ocaml
let apply_operator ~loc op expr _ty =
  match op with
  | Default -> yojson_of_value ~loc expr None
  (* ... *)
```

### Step 3: Remove Dead Helper Functions

Check if any helper functions are now unused after Step 1:
- Pattern matching helpers for specific types
- Type deconstruction utilities
- Container element conversion logic

If found, remove them and update `.mli` if needed.

### Step 4: Update Documentation Comments

**File:** `ppx/code_generator.ml`

Update the module-level documentation:

```ocaml
(** Code generator for template expansion

    Note: This module uses runtime type conversion via Runtime_helpers.generic_to_json
    because PPX expansion occurs before type checking. Type-specific conversions
    cannot be performed at compile time.
*)
```

### Step 5: Update or Remove `Safe_conversions` Module

**File:** `lib/runtime_helpers.ml`

The `Safe_conversions` module (lines 96-124) was created to provide type-safe conversions:

```ocaml
module Safe_conversions = struct
  type 'a t = 'a -> Yojson.Safe.t
  let string : string t = make string_to_json
  let int : int t = make int_to_json
  (* ... etc ... *)
```

**Decision needed:** 
- If it has external users: Keep but document as manual alternative
- If only for internal use: Remove since it's unused internally

**Check usage:**
```bash
grep -r "Safe_conversions" --include="*.ml" --include="*.mli"
```

### Step 6: Verify Type-Specific Helpers in Runtime_helpers

**File:** `lib/runtime_helpers.ml`

The type-specific conversion functions (lines 4-52) are still used:

```ocaml
let string_to_json s = `String s
let int_to_json i = `Int i
let float_to_json f = `Float f
(* ... etc ... *)
```

**Keep these** - they are:
- Used internally by `generic_to_json` for known types
- Part of the public API for manual conversion
- Referenced by documentation

**Verification:**
```bash
grep -r "string_to_json\|int_to_json\|float_to_json" --include="*.ml" --include="*.mli"
```

### Step 7: Update Test Files

**Files:**
- `test/test_type_coverage.ml` - Tests that verify type conversion behavior
- `test/test_ppx_comprehensive.ml` - Tests type annotations

**Review tests that use explicit type annotations:**

```ocaml
(* In test_mixed_types *)
let str_val : string = "text" in
let int_val : int = 42 in
[%template "{str_val}, {int_val}"]
```

These tests should still pass (they use `generic_to_json` anyway), but verify:
- Remove any test comments suggesting type annotations affect code generation
- Add comments explaining that type annotations don't affect PPX output

### Step 8: Update PPX Documentation

**File:** `ppx/AGENTS.md`

Update the "Type Conversion Fallback Chain" section:

```markdown
### Type Conversion (Simplified)

PPX expansion occurs before type checking, so compile-time type detection is not possible.
All template variables use `Runtime_helpers.generic_to_json` for JSON conversion.

**Previous Documentation (incorrect):**
1. PPX tries compile-time type detection first (int, string, float, etc.)
2. Falls back to `Runtime_helpers.generic_to_json` for unknown types
3. Obj module runtime inspection used only as last resort

**Correct Documentation:**
1. PPX cannot determine types at compile time (runs before type checker)
2. All variables use `generic_to_json` which inspects values at runtime
3. Obj module is used for runtime type introspection
```

### Step 9: Update Main Documentation

**File:** `README.md` (if it mentions compile-time type optimization)

Remove or correct any claims about:
- "Compile-time type detection"
- "Type-specific optimization"
- "Zero-overhead for known types"

Replace with accurate description of runtime type introspection.

## Testing Strategy

### 1. Build Verification

```bash
# Clean build
dune clean && dune build @install

# Verify no compilation errors
dune build @check
```

### 2. Functionality Tests

```bash
# Run PPX tests
dune exec test/test_ppx_comprehensive.exe

# Run type coverage tests
dune exec test/test_type_coverage.exe

# Run all tests
dune build @runtest
```

### 3. Dead Code Verification

```bash
# Check for unused code warnings
dune build --profile dev 2>&1 | grep -i "unused"

# Verify no references to removed functions
grep -r "string_to_json\|int_to_json\|float_to_json" ppx/
# Should only show references in Runtime_helpers, not PPX
```

### 4. Behavior Verification

Create a test file to verify behavior is identical:

```ocaml
(* test_dead_code_removal.ml *)
let test_behavior_unchanged () =
  (* Before and after cleanup, this should produce identical output *)
  let x = 42 in
  let y = "hello" in
  let z = 3.14 in
  let msg, json = [%template "Values: {x}, {y}, {z}"] in
  
  (* Verify message format *)
  assert (String.contains msg '4');
  assert (String.contains msg 'h');
  assert (String.contains msg '3');
  
  (* Verify JSON structure *)
  let json_str = Yojson.Safe.to_string json in
  assert (String.contains json_str "42");
  assert (String.contains json_str "hello");
  assert (String.contains json_str "3.14")
```

## Files to Modify

| File | Changes |
|------|---------|
| `ppx/code_generator.ml` | Remove dead type-specific branches, simplify `yojson_of_value` and `apply_operator` |
| `ppx/AGENTS.md` | Update type conversion documentation |
| `lib/runtime_helpers.ml` | Potentially remove `Safe_conversions` module |
| `lib/runtime_helpers.mli` | Update interface if `Safe_conversions` removed |
| `test/test_type_coverage.ml` | Update comments about type annotations |
| `test/test_ppx_comprehensive.ml` | Update comments about type annotations |
| `README.md` | Remove claims about compile-time type detection |

## Files to Review (No Changes Expected)

| File | Review Purpose |
|------|----------------|
| `ppx/scope_analyzer.ml` | Confirm type extraction is intentionally not implemented |
| `ppx/ppx_message_templates.ml` | Confirm no type-specific logic in main PPX |
| All other test files | Verify no test relies on compile-time type detection |

## Success Criteria

- [ ] `ppx/code_generator.ml` has no dead type-specific branches
- [ ] `yojson_of_value` function is simplified to single code path
- [ ] All tests pass without modification (behavior unchanged)
- [ ] No compiler warnings about unused code
- [ ] Documentation accurately reflects runtime-only type conversion
- [ ] `Safe_conversions` module either removed or documented
- [ ] Code coverage shows increase (dead code removed from denominator)

## Rollback Plan

If issues are discovered:

1. **Revert commit**: `git revert <commit-hash>`
2. **Alternative approach**: Instead of removing, mark dead code with `[@@alert deprecated "Dead code - will be removed"]`
3. **Gradual removal**: Comment out code first, verify in production, then delete

## Related Plans

- **Plan 02 (Remove Obj Usage)**: Complementary - Plan 10 removes dead code, Plan 02 removes Obj dependency
- **Plan 06 (Add Comprehensive Tests)**: Tests should verify behavior is unchanged
- **Plan 09 (Remove Async Sink Queue)**: Independent, can proceed in parallel

## Notes

### Why Not Make Type Detection Work?

Several approaches were considered but rejected for this plan:

1. **Compiler hooks**: Would require custom compiler patches, breaks compatibility
2. **PPX rewriters chaining**: Complex, fragile, still limited
3. **Typed PPX (ppxlib phases)**: Only works after type checking, incompatible with current architecture
4. **Explicit type annotations**: Would require new syntax like `{(x : int)}`, breaking change

**Decision**: Accept limitation, document it, clean up dead code.

### Future Enhancement (Out of Scope)

If compile-time type detection is desired in the future:

1. Create new plan for explicit type annotation syntax
2. Implement `{(var : type)}` syntax in template parser
3. Add type-aware code generation path
4. Maintain backward compatibility with existing syntax

This is a **new feature**, not a **cleanup**, and requires separate planning.
