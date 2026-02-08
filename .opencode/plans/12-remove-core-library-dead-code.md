# Plan 12: Remove Dead Code from Core Library

## Status
**Priority:** MEDIUM  
**Estimated Effort:** 3-4 hours  
**Risk Level:** Low (code cleanup, no behavioral changes)  
**Dependencies:** Plan 10 (PPX dead code), Plan 11 (Safe_conversions dead code) - can proceed independently

## Overview

This plan identifies and removes dead code from the core library (`lib/` directory) that is never executed or referenced. This complements Plans 10 and 11 which focus on PPX and Runtime_helpers dead code respectively.

## Problem Statement

The core library contains several categories of dead code:

1. **Unused module type definitions** - Interface definitions never implemented or used
2. **Unused record fields** - Fields that are set but never read
3. **Unused convenience operators** - Operators defined but never called
4. **Legacy functions** - Superseded by newer implementations

### Dead Code Inventory

#### Category 1: Logger Module Type Definitions (Dead Code)

**Location:** `lib/logger.mli` lines 44-57

```ocaml
(** Enricher signature - adds properties to log events *)
module type ENRICHER = sig
  type t
  val enrich : t -> Log_event.t -> Log_event.t
end

(** Filter signature - determines if an event should be logged *)
module type FILTER = sig
  type t
  val is_included : t -> Log_event.t -> bool
end
```

**Why Dead:**
- These module types are duplicated in `lib/logger.ml` (lines 4-15)
- Neither the .mli nor .ml versions are ever used as actual signatures
- Enrichers are implemented as simple functions `(Log_event.t -> Log_event.t)`
- Filters are implemented as simple functions `(Log_event.t -> bool)`
- No module ever declares `module MyEnricher : Logger.ENRICHER`

**Verification:**
```bash
grep -r "ENRICHER" --include="*.ml" --include="*.mli" lib/ test/ examples/
# Only found in logger.mli and logger.ml - never used elsewhere

grep -r "FILTER" --include="*.ml" --include="*.mli" lib/ test/ examples/ | grep -v "filter"
# Only found in logger.mli and logger.ml - never used elsewhere
```

#### Category 2: Logger source Field (Dead Code)

**Location:** `lib/logger.ml` line 57

```ocaml
type logger_impl =
  { min_level: Level.t
  ; sinks: (Composite_sink.sink_fn * Level.t option) list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: (Log_event.t -> bool) list
  ; context_properties: (string * Yojson.Safe.t) list
  ; source: string option }  (* <-- DEAD FIELD *)
```

**Why Dead:**
- The `source` field is set by `for_source` function (line 166)
- The `for_source` function is exposed in the interface (logger.mli line 99)
- BUT: The `source` field is **never read anywhere in the codebase**
- No logging output includes the source field
- No filtering uses the source field
- It's purely decorative

**Verification:**
```bash
grep -r "\.source" --include="*.ml" lib/ 
# No matches - the field is never accessed

grep -r "for_source" --include="*.ml" lib/
# Found: only used to SET the field, never to READ it
```

**Related:** The `for_source` function itself becomes dead code if the field is removed.

#### Category 3: Level Comparison Operators (Dead Code)

**Location:** `lib/level.ml` lines 57-72, `lib/level.mli` lines 26-42

```ocaml
(** Check if level a is greater than or equal to level b *)
let (>=) a b = compare a b >= 0

(** Check if level a is less than level b *)
let (<) a b = compare a b < 0

(** Check if level a is greater than level b *)
let (>) a b = compare a b > 0

(** Check if level a is less than or equal to level b *)
let (<=) a b = compare a b <= 0

(** Check if two levels are equal *)
let (=) a b = compare a b = 0

(** Check if two levels are not equal *)
let (<>) a b = compare a b <> 0
```

**Why Dead:**
- These infix operators are defined but **never used anywhere**
- All comparisons use `Level.compare` directly:
  - `Level.compare level t.min_level >= 0` (logger.ml)
  - `Level.compare event_level min_level >= 0` (filter.ml)
  - `Level.compare level min_lvl < 0` (logger.ml, various configuration files)
- The operators were designed for convenience but never adopted

**Verification:**
```bash
grep -r "Level\.(>=" --include="*.ml" lib/ test/ examples/
# No matches

grep -r "Level\.(<\|>\|<=\|=\|<>\)" --include="*.ml" lib/ test/ examples/
# No matches (except in level.ml itself)
```

**Note:** These operators shadow the built-in comparison operators when `open Level` is used, which could cause subtle bugs. Removing them is a bug fix.

#### Category 4: Log_event.escape_json_string (Deprecated/Legacy)

**Location:** `lib/log_event.ml` lines 57-61

```ocaml
(** Escape a string for JSON output (kept for backward compatibility) *)
let escape_json_string s =
  let buf = Buffer.create (String.length s + 10) in
  append_escaped_string buf s;
  Buffer.contents buf
;;
```

**Why Dead:**
- Comment says "kept for backward compatibility" but no one uses it
- Superseded by `append_escaped_string` (lines 40-54) which avoids intermediate allocation
- The newer `append_escaped_string` is used in `to_json_string`
- Only referenced in test files and old plans

**Verification:**
```bash
grep -r "escape_json_string" --include="*.ml" lib/ ppx/ test/ examples/
# Only found in:
# - log_event.ml (definition)
# - .opencode/plans/06-add-comprehensive-tests.md (reference)
```

#### Category 5: Metrics.bytes_written Field (Dead Data)

**Location:** `lib/metrics.ml`

The `bytes_written` field is initialized to 0 but **never updated**:

```ocaml
type sink_data =
  { mutable events_total: int
  ; mutable events_dropped: int
  ; mutable events_failed: int
  ; mutable bytes_written: int  (* <-- NEVER UPDATED *)
  ; mutable last_error: (exn * float) option
  ; latencies: float Queue.t
  ; mutable p50: float
  ; mutable p95: float }

let get_sink_data_locked t sink_id =
  match Hashtbl.find_opt t.sinks sink_id with
  | Some d -> d
  | None ->
      let d =
        { events_total= 0
        ; events_dropped= 0
        ; events_failed= 0
        ; bytes_written= 0  (* <-- Initialized but never modified *)
        ; last_error= None
        ; latencies= Queue.create ()
        ; p50= 0.0
        ; p95= 0.0 }
      in
      Hashtbl.add t.sinks sink_id d;
      d
```

**Why Dead:**
- The field is never updated after initialization
- All reads return 0
- If metrics tracking is needed, it should be implemented properly
- If not needed, it should be removed to avoid confusion

**Verification:**
```bash
grep -r "bytes_written.*<-" --include="*.ml" lib/
# No matches - never assigned after initialization
```

## Solution

### Step 1: Remove ENRICHER and FILTER Module Types

**Files:** `lib/logger.mli`, `lib/logger.ml`

**In logger.mli - Remove lines 44-57:**
```ocaml
(** REMOVE THIS ENTIRE SECTION **)
(** Enricher signature - adds properties to log events *)
module type ENRICHER = sig
  type t
  val enrich : t -> Log_event.t -> Log_event.t
end

(** Filter signature - determines if an event should be logged *)
module type FILTER = sig
  type t
  val is_included : t -> Log_event.t -> bool
end
```

**In logger.ml - Remove lines 4-15:**
```ocaml
(** REMOVE THIS ENTIRE SECTION **)
(** Enricher signature *)
module type ENRICHER = sig
  type t
  val enrich : t -> Log_event.t -> Log_event.t
end

(** Filter signature *)
module type FILTER = sig
  type t
  val is_included : t -> Log_event.t -> bool
end
```

**Rationale:** These are interface definitions with no implementations and no users. They clutter the API and suggest a pattern that doesn't exist.

### Step 2: Remove source Field and for_source Function

**Files:** `lib/logger.ml`, `lib/logger.mli`, `lib/log.ml`, `lib/log.mli`

**In logger.ml:**

1. Remove `source` field from `logger_impl` type (line 57):
```ocaml
type logger_impl =
  { min_level: Level.t
  ; sinks: (Composite_sink.sink_fn * Level.t option) list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: (Log_event.t -> bool) list
  ; context_properties: (string * Yojson.Safe.t) list }
  (* source field removed *)
```

2. Remove `for_source` function (lines 165-166):
```ocaml
(* REMOVE THIS FUNCTION *)
let for_source t source_name = {t with source= Some source_name}
```

3. Remove `source` from `create` function (line 175):
```ocaml
let create ~min_level ~sinks =
  { min_level
  ; sinks
  ; enrichers= []
  ; filters= []
  ; context_properties= [] }
  (* source removed *)
```

4. Remove `for_source` from `S` module type in logger.ml (line 43):
```ocaml
module type S = sig
  type t
  val write : ...
  (* ... other functions ... *)
  (* REMOVE: val for_source : t -> string -> t *)
end
```

**In logger.mli:**

1. Remove `for_source` from the main interface (line 99):
```ocaml
(* REMOVE THIS LINE *)
val for_source : t -> string -> t
```

2. Remove `for_source` from `S` module type (line 33):
```ocaml
(* REMOVE THIS LINE *)
val for_source : t -> string -> t
```

**In log.mli:**

Remove `for_source` function (line 35):
```ocaml
(* REMOVE THIS LINE *)
val for_source : string -> Logger.t
```

**In log.ml:**

Remove `for_source` function (lines 65-68):
```ocaml
(* REMOVE THIS ENTIRE FUNCTION *)
let for_source source_name =
  match !global_logger with
  | Some logger -> Logger.for_source logger source_name
  | None -> Logger.create ~min_level:Level.Fatal ~sinks:[]
```

**In async packages:**

Update `message-templates-lwt/lib/lwt_logger.ml` - remove `for_source` function (line 114).

Update `message-templates-eio/lib/eio_logger.ml` - remove `for_source` function (line 147).

**Rationale:** The feature is not implemented - storing a source value that is never used is confusing and wasteful. If source tracking is needed in the future, it should be implemented as an enricher that adds a `Source` property to events.

### Step 3: Remove Level Comparison Operators

**Files:** `lib/level.ml`, `lib/level.mli`

**In level.ml - Remove lines 57-72:**
```ocaml
(* REMOVE ALL THESE OPERATORS *)
let (>=) a b = compare a b >= 0
let (<) a b = compare a b < 0
let (>) a b = compare a b > 0
let (<=) a b = compare a b <= 0
let (=) a b = compare a b = 0
let (<>) a b = compare a b <> 0
```

**In level.mli - Remove lines 26-42:**
```ocaml
(* REMOVE ALL THESE OPERATOR DECLARATIONS *)
val (>=) : t -> t -> bool
val (<) : t -> t -> bool
val (>) : t -> t -> bool
val (<=) : t -> t -> bool
val (=) : t -> t -> bool
val (<>) : t -> t -> bool
```

**Rationale:** These operators are never used and shadow the built-in operators when `open Level` is used, which can cause subtle bugs.

### Step 4: Remove escape_json_string Function

**Files:** `lib/log_event.ml`, `lib/log_event.mli`

**In log_event.ml - Remove lines 56-61:**
```ocaml
(* REMOVE THIS FUNCTION *)
(** Escape a string for JSON output (kept for backward compatibility) *)
let escape_json_string s =
  let buf = Buffer.create (String.length s + 10) in
  append_escaped_string buf s;
  Buffer.contents buf
;;
```

**In log_event.mli - Remove from interface:**
```ocaml
(* REMOVE THIS DECLARATION if present - check if it's exported *)
```

**Rationale:** The function is superseded by `append_escaped_string` which is more efficient (avoids intermediate buffer allocation). Keeping dead "backward compatibility" code forever doesn't help anyone.

### Step 5: Remove or Implement Metrics.bytes_written

**Decision Required:** Either implement proper byte tracking or remove the field.

**Option A - Remove (Recommended for now):**

**Files:** `lib/metrics.ml`, `lib/metrics.mli`

**In metrics.ml:**
1. Remove `bytes_written` from `sink_data` type (line 18)
2. Remove `bytes_written= 0` from initialization (line 68)
3. Remove `bytes_written= data.bytes_written` from `get_sink_metrics` (line 121)
4. Remove `bytes_written= data.bytes_written` from `get_all_metrics` (line 137)
5. Remove from `to_json` output (line 168)

**In metrics.mli:**
1. Remove `bytes_written` from `sink_metrics` record (line 31)

**In test_metrics.ml:**
Remove any assertions about `bytes_written`.

**Option B - Implement:**
If byte tracking is desired, add byte counting to each sink's emit function and pass the byte count to `record_event`. This is more complex and should be a separate feature plan.

**Rationale:** A field that always returns 0 is misleading and suggests broken functionality.

## Implementation Order

The steps should be done in order to avoid breaking the build:

1. **Step 1** - Remove ENRICHER/FILTER (safest - just interfaces)
2. **Step 2** - Remove source/for_source (requires updating async packages)
3. **Step 3** - Remove Level operators (purely additive removal)
4. **Step 4** - Remove escape_json_string (internal function)
5. **Step 5** - Handle bytes_written (requires test updates)

## Testing Strategy

### Build Verification
```bash
# Clean build
dune clean && dune build @install

# Type checking
dune build @check
```

### Test Verification
```bash
# Run all tests
dune build @runtest

# Run specific test modules affected by changes
dune exec test/test_logger.exe
dune exec test/test_level.exe
dune exec test/test_metrics.exe
dune exec test/test_log_event.exe

# Run async tests
dune exec message-templates-lwt/test/test_lwt_logger.exe
dune exec message-templates-eio/test/test_eio_logger.exe
```

### Dead Code Verification
```bash
# Check for unused code warnings
dune build --profile dev 2>&1 | grep -i "unused"

# Verify removed functions are no longer referenced
grep -r "for_source\|escape_json_string" --include="*.ml" lib/ test/ examples/ || echo "Good - no references found"
```

## Files to Modify

| File | Changes |
|------|---------|
| `lib/logger.mli` | Remove ENRICHER/FILTER module types, for_source val |
| `lib/logger.ml` | Remove ENRICHER/FILTER module types, source field, for_source function |
| `lib/log.mli` | Remove for_source val |
| `lib/log.ml` | Remove for_source function |
| `lib/level.mli` | Remove comparison operators |
| `lib/level.ml` | Remove comparison operators |
| `lib/log_event.ml` | Remove escape_json_string function |
| `lib/log_event.mli` | Remove escape_json_string export if present |
| `lib/metrics.mli` | Remove bytes_written field |
| `lib/metrics.ml` | Remove bytes_written field from types and functions |
| `test/test_metrics.ml` | Remove bytes_written assertions |
| `message-templates-lwt/lib/lwt_logger.ml` | Remove for_source function |
| `message-templates-eio/lib/eio_logger.ml` | Remove for_source function |

## Success Criteria

- [ ] All removed code is confirmed to be unused (verified by grep)
- [ ] All tests pass without modification (except metrics bytes_written tests)
- [ ] No compiler warnings about unused code
- [ ] Async packages (Lwt/Eio) are updated to match core changes
- [ ] Code coverage percentage increases (dead code removed from denominator)
- [ ] Documentation updated to reflect API changes

## Rollback Plan

If issues are discovered:

1. **Revert commit:** `git revert <commit-hash>`
2. **Staged removal:** If full removal causes issues, deprecate first with `[@@deprecated "Will be removed"]`
3. **Feature restoration:** If `source` field was actually needed, implement proper source tracking as an enricher

## Related Plans

- **Plan 10 (Remove PPX Dead Code):** Independent - can proceed in parallel
- **Plan 11 (Remove Safe_conversions):** Independent - can proceed in parallel
- **Future Plan - Implement Source Tracking:** If source tracking is desired, implement as:
  ```ocaml
  let with_source t source_name =
    with_enricher t (fun event ->
      Log_event.add_property event "Source" (`String source_name))
  ```

## Notes

### Why Not Deprecate Instead of Remove?

For internal dead code that is:
- Never referenced in any file
- Never tested (except the metrics field)
- Never documented as public API

Deprecation adds noise without benefit. These removals are safe.

### Exception: Metrics.bytes_written

This field IS part of the public API (exposed in `sink_metrics` record). If external users might access it, consider:
1. Deprecating first in one release
2. Removing in next release

Check with: `grep -r "bytes_written" --include="*.ml" examples/` to see if examples use it.

## Verification Commands

Before starting implementation, verify dead code status:

```bash
# Verify ENRICHER/FILTER are unused
echo "=== ENRICHER usage ==="
grep -r "ENRICHER" --include="*.ml" --include="*.mli" lib/ test/ examples/ | grep -v "logger.mli\|logger.ml"
echo "=== FILTER usage ==="
grep -r ": FILTER" --include="*.ml" --include="*.mli" lib/ test/ examples/ | grep -v "logger.mli\|logger.ml"

# Verify source field is unread
echo "=== source field reads ==="
grep -r "\.source" --include="*.ml" lib/ | grep -v "source_name"

# Verify Level operators are unused
echo "=== Level operator usage ==="
grep -r "Level\.(>=" --include="*.ml" lib/ test/ examples/
grep -r "Level\.(<\|>\|<=\|=\|<>\))" --include="*.ml" lib/ test/ examples/ | grep -v "Level.compare"

# Verify escape_json_string is unused
echo "=== escape_json_string usage ==="
grep -r "escape_json_string" --include="*.ml" lib/ test/ examples/ | grep -v "log_event.ml"

# Verify bytes_written is unassigned
echo "=== bytes_written assignments ==="
grep -r "bytes_written.*<-" --include="*.ml" lib/
```

If all these return no results (except the definition locations), the code is confirmed dead.
