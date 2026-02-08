# Plan 11: Remove Safe_conversions and Type-Specific Converter Dead Code

## Status
**Priority:** MEDIUM  
**Estimated Effort:** 1-2 hours  
**Risk Level:** Low (code cleanup, no behavioral changes)  
**Dependencies:** Plan 10 (should complete first for clean separation)

## Problem Statement

The `Safe_conversions` module and all type-specific converters (`string_to_json`, `int_to_json`, etc.) in `lib/runtime_helpers.ml` are completely unused dead code.

### Current Dead Code Analysis

In `lib/runtime_helpers.ml`:

```ocaml
(** Lines 4-52: Type-specific converters - ALL UNUSED *)
let string_to_json s = `String s           (* UNUSED *)
let int_to_json i = `Int i                 (* UNUSED *)
let float_to_json f = `Float f             (* UNUSED *)
let bool_to_json b = `Bool b               (* UNUSED *)
let int64_to_json i = `Intlit ...          (* UNUSED *)
let int32_to_json i = `Intlit ...          (* UNUSED *)
let nativeint_to_json i = `Intlit ...      (* UNUSED *)
let char_to_json c = `String ...           (* UNUSED *)
let unit_to_json () = `Null                (* UNUSED *)
let list_to_json f lst = ...               (* UNUSED *)
let array_to_json f arr = ...              (* UNUSED *)
let option_to_json f = function ...        (* UNUSED *)
let result_to_json f_ok f_err = ...        (* UNUSED *)
let pair_to_json f1 f2 = ...               (* UNUSED *)
let triple_to_json f1 f2 f3 = ...          (* UNUSED *)

(** Lines 96-124: Safe_conversions module - COMPLETELY UNUSED *)
module Safe_conversions = struct
  type 'a t = 'a -> Yojson.Safe.t
  let make : 'a. ('a -> Yojson.Safe.t) -> 'a t = fun f -> f
  let string : string t = make string_to_json      (* References dead code *)
  let int : int t = make int_to_json               (* References dead code *)
  (* ... all unused ... *)
end
```

### Why This Code Is Dead

**`generic_to_json` uses Obj directly** (lines 284-320):
```ocaml
let generic_to_json (type a) (v : a) : Yojson.Safe.t =
  let module O = Obj in
  let rec convert repr =
    if O.is_int repr then
      `Int (O.obj repr)                    (* Uses Obj, not int_to_json *)
    else if O.is_block repr then
      match O.tag repr with
      | 252 -> `String (O.obj repr : string)  (* Uses Obj, not string_to_json *)
      | 253 -> `Float (O.obj repr : float)    (* Uses Obj, not float_to_json *)
      (* ... etc ... *)
      | _ -> `String (generic_to_string v)
  in
  convert (O.repr v)
```

The Obj-based implementation bypasses all type-specific converters entirely.

### Code Usage Verification

```bash
# Type-specific converters only referenced by Safe_conversions
$ grep -r "string_to_json\|int_to_json\|float_to_json" --include="*.ml" lib/ ppx/ test/ examples/
lib/runtime_helpers.ml:    (defined)
lib/runtime_helpers.ml:    (used only in Safe_conversions module)

# Safe_conversions never used
$ grep -r "Safe_conversions" --include="*.ml" lib/ ppx/ test/ examples/
lib/runtime_helpers.ml:    (module definition)
lib/runtime_helpers.mli:   (interface definition)
lib/messageTemplates.ml:   (re-export)
# No actual usage found

# PPX only uses generic_to_json
$ grep -r "Runtime_helpers" ppx/
ppx/code_generator.ml:  Message_templates.Runtime_helpers.generic_to_json
```

### Impact of Dead Code

- **~60 lines of completely unreachable code**
- **Maintenance burden**: Keeping unused code in sync with changes
- **Confusion**: Suggests a type-safe conversion path exists when it doesn't
- **Documentation drift**: `Safe_conversions` documented as public API but never used
- **Build time**: Slightly slower compilation (minimal but real)

## Solution

Remove all type-specific converters and the `Safe_conversions` module. Keep `generic_to_json` and `generic_to_string` as they are the only converters actually used.

### Rationale

- **Zero behavioral change**: No code calls these functions
- **Simpler codebase**: Remove confusing unused abstractions
- **Clear architecture**: Makes it obvious that only Obj-based conversion is used
- **Easier future refactoring**: No need to maintain parallel conversion paths

## Implementation Steps

### Step 1: Remove Type-Specific Converters

**File:** `lib/runtime_helpers.ml`

**Remove lines 4-62** (from `string_to_json` through `triple_to_json`):

```ocaml
(** KEEP THESE - used by render_template *)
let json_to_string = function ...
let replace_all template pattern replacement = ...
let render_template template properties = ...

(** REMOVE THESE - completely unused *)
let string_to_json s = `String s
let int_to_json i = `Int i
let float_to_json f = `Float f
let bool_to_json b = `Bool b
let int64_to_json i = `Intlit (Int64.to_string i)
let int32_to_json i = `Intlit (Int32.to_string i)
let nativeint_to_json i = `Intlit (Nativeint.to_string i)
let char_to_json c = `String (String.make 1 c)
let unit_to_json () = `Null
let list_to_json f lst = `List (List.map f lst)
let array_to_json f arr = `List (Array.to_list (Array.map f arr))
let option_to_json f = function
  | None -> `Null
  | Some v -> f v
let result_to_json f_ok f_err = function
  | Ok v -> `Assoc [("Ok", f_ok v)]
  | Error e -> `Assoc [("Error", f_err e)]
let pair_to_json f1 f2 (a, b) = `List [f1 a; f2 b]
let triple_to_json f1 f2 f3 (a, b, c) = `List [f1 a; f2 b; f3 c]

(** KEEP Safe_conversions for now - will remove in Step 2 *)
```

### Step 2: Remove Safe_conversions Module

**File:** `lib/runtime_helpers.ml`

**Remove lines 96-124** (the entire `Safe_conversions` module):

```ocaml
(** REMOVE ENTIRE MODULE - completely unused *)
module Safe_conversions = struct
  type 'a t = 'a -> Yojson.Safe.t
  let make : 'a. ('a -> Yojson.Safe.t) -> 'a t = fun f -> f
  let string : string t = make string_to_json
  let int : int t = make int_to_json
  let float : float t = make float_to_json
  let bool : bool t = make bool_to_json
  let int64 : int64 t = make int64_to_json
  let int32 : int32 t = make int32_to_json
  let nativeint : nativeint t = make nativeint_to_json
  let char : char t = make char_to_json
  let unit : unit t = make unit_to_json
  let list : 'a. 'a t -> 'a list t = fun f -> make (list_to_json f)
  let array : 'a. 'a t -> 'a array t = fun f -> make (array_to_json f)
  let option : 'a. 'a t -> 'a option t = fun f -> make (option_to_json f)
end
```

### Step 3: Update Interface File

**File:** `lib/runtime_helpers.mli`

**Remove all type-specific converter declarations** (lines 9-64):

```ocaml
(** REMOVE - string_to_json through triple_to_json *)
val string_to_json : string -> Yojson.Safe.t
val int_to_json : int -> Yojson.Safe.t
val float_to_json : float -> Yojson.Safe.t
val bool_to_json : bool -> Yojson.Safe.t
val int64_to_json : int64 -> Yojson.Safe.t
val int32_to_json : int32 -> Yojson.Safe.t
val nativeint_to_json : nativeint -> Yojson.Safe.t
val char_to_json : char -> Yojson.Safe.t
val unit_to_json : unit -> Yojson.Safe.t
val list_to_json : ('a -> Yojson.Safe.t) -> 'a list -> Yojson.Safe.t
val array_to_json : ('a -> Yojson.Safe.t) -> 'a array -> Yojson.Safe.t
val option_to_json : ('a -> Yojson.Safe.t) -> 'a option -> Yojson.Safe.t
val result_to_json : ('a -> Yojson.Safe.t) -> ('e -> Yojson.Safe.t) -> ('a, 'e) result -> Yojson.Safe.t
val pair_to_json : ('a -> Yojson.Safe.t) -> ('b -> Yojson.Safe.t) -> 'a * 'b -> Yojson.Safe.t
val triple_to_json : ('a -> Yojson.Safe.t) -> ('b -> Yojson.Safe.t) -> ('c -> Yojson.Safe.t) -> 'a * 'b * 'c -> Yojson.Safe.t

(** REMOVE - Safe_conversions section *)
module Safe_conversions : sig ... end
```

**Update documentation header** to remove references to Safe_conversions:

```ocaml
(** Safe runtime conversions for Message Templates

    This module provides runtime type conversions between OCaml values and JSON
    representations using Obj module introspection. All template variables use
    the generic conversion functions.
*)
```

### Step 4: Remove from Module Exports

**File:** `lib/messageTemplates.ml`

The `Runtime_helpers` module is already aliased:
```ocaml
module Runtime_helpers = Runtime_helpers
```

This stays, but the `Safe_conversions` submodule will no longer be accessible through it (which is fine since nothing uses it).

### Step 5: Update AGENTS.md Documentation

**Files:**
- `lib/AGENTS.md` - Remove references to Safe_conversions
- `AGENTS.md` (root) - Remove references to type-specific converters
- `ppx/AGENTS.md` - Update type conversion section

Remove sections like:
- "Type Conversion Architecture" (the new section we added in Plan 10)
- References to `Safe_conversions` in public API

### Step 6: Verify No References Remain

**Command to run:**
```bash
grep -r "string_to_json\|int_to_json\|float_to_json\|bool_to_json\|int64_to_json\|int32_to_json\|nativeint_to_json\|char_to_json\|unit_to_json\|list_to_json\|array_to_json\|option_to_json\|result_to_json\|pair_to_json\|triple_to_json" --include="*.ml" --include="*.mli" lib/ ppx/ test/ examples/ 2>/dev/null
```

**Expected result:** No matches (or only in comments if we keep any)

### Step 7: Format Code

```bash
dune build --auto-promote @fmt
```

## Testing Strategy

### 1. Build Verification

```bash
# Clean build
dune clean && dune build @install

# Type-check
dune build @check

# Format check
dune build @fmt
```

### 2. Functionality Tests

```bash
# All tests must pass
dune build @runtest

# PPX-specific tests
dune exec test/test_ppx_comprehensive.exe
dune exec test/test_type_coverage.exe

# Core library tests
dune exec test/test_logger.exe
dune exec test/test_sinks.exe
```

### 3. Interface Verification

```bash
# Check no symbols are missing from exported API
# (There should be no external users of these functions)
```

### 4. Dead Code Verification

```bash
# Verify removed functions are truly gone
grep -r "Safe_conversions" lib/ ppx/ test/ examples/ 2>/dev/null | grep -v "AGENTS.md"
# Should return nothing
```

## Files to Modify

| File | Changes |
|------|---------|
| `lib/runtime_helpers.ml` | Remove type-specific converters (lines 4-62) and Safe_conversions module (lines 96-124) |
| `lib/runtime_helpers.mli` | Remove all type-specific converter declarations and Safe_conversions signature |
| `lib/AGENTS.md` | Remove documentation about Safe_conversions and type-specific converters |
| `AGENTS.md` (root) | Remove references to type conversion architecture |

## Files to Review (No Changes Expected)

| File | Review Purpose |
|------|----------------|
| `ppx/code_generator.ml` | Confirm it only uses `generic_to_json` |
| `test/test_type_coverage.ml` | Confirm tests don't reference removed functions |
| `examples/*.ml` | Confirm examples don't use Safe_conversions |

## Success Criteria

- [ ] `lib/runtime_helpers.ml` reduced by ~60 lines
- [ ] `lib/runtime_helpers.mli` reduced by ~70 lines
- [ ] All type-specific converters removed
- [ ] `Safe_conversions` module removed
- [ ] All tests pass without modification
- [ ] No compiler warnings
- [ ] No references to removed functions remain in codebase
- [ ] Documentation updated to reflect simplified API

## Rollback Plan

If issues are discovered:

1. **Revert commit**: `git revert <commit-hash>`
2. **Check for external users**: If external code uses these functions, they should be deprecated first:
   ```ocaml
   [@@ocaml.deprecated "Use generic_to_json instead"]
   let string_to_json s = `String s
   ```

## Breaking Change Assessment

### Public API Changes

**Before:**
```ocaml
Message_templates.Runtime_helpers.string_to_json
Message_templates.Runtime_helpers.Safe_conversions
```

**After:**
```ocaml
(* No longer available *)
```

### Impact Analysis

- **Internal codebase**: Zero impact (nothing uses these)
- **External users**: Potential breaking change if anyone uses these functions
- **Mitigation**: Since we have no evidence of external use, proceed with removal
- **Documentation**: AGENTS.md files should clearly document that only `generic_to_json` is used

## Related Plans

- **Plan 10 (Remove PPX Dead Code)**: Complementary - removes dead code in PPX
- **Plan 11 (This Plan)**: Removes dead code in runtime helpers
- **Plan 02 (Remove Obj Usage)**: Future plan to replace Obj-based conversion with explicit converters (if desired)

## Notes

### Future Type-Safe Conversion

If explicit type-safe conversion is needed in the future, it should be implemented as:

1. **New syntax in templates**: `{(var : int)}` for explicit type annotations
2. **PPX code generation**: Generate calls to specific converters based on explicit annotations
3. **Runtime converters**: May re-add type-specific converters at that time

This is different from the current dead code because:
- Current code was never integrated with PPX
- Current code was never used by anything
- Future implementation would be purpose-built with PPX support

### Why Not Keep As "Future Use"

The dead code has been present for a long time without being used. Keeping it:
- Creates maintenance burden
- Creates false expectations about functionality
- Makes the codebase harder to understand
- Can be easily re-added if/when actually needed

## Alternative: Deprecation First

If there's concern about breaking external users, an alternative approach is:

1. Add `[@@ocaml.deprecated]` attributes to all functions and the module
2. Release a version with deprecation warnings
3. Wait for feedback (are people using these?)
4. Remove in a subsequent version

However, given:
- No usage in tests, examples, or internal code
- No documentation encouraging their use
- The PPX doesn't support using them

**Recommendation**: Proceed with direct removal.
