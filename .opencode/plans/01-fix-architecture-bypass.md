# Plan 1: Fix Architecture Bypass (Logger → Composite_sink.emit)

## Status
**Priority:** HIGH  
**Estimated Effort:** 2-3 hours  
**Risk Level:** Medium (requires careful refactoring)

## Problem Statement

The `Logger.write` function directly iterates over sinks and calls their `emit_fn`, bypassing `Composite_sink.emit`. This creates:

1. **Duplicated filtering logic** - Per-sink level filtering exists in both `Configuration.add_sink` (wrapping emit_fn) AND `Composite_sink.emit`
2. **Inconsistent behavior** - `Composite_sink.emit` is only used by external consumers, not internal Logger use
3. **Maintenance burden** - Changes to sink routing require updates in multiple places

### Current Flow (Problematic)
```
Logger.write
  ├─ is_enabled check (fast path)
  ├─ create Log_event
  ├─ apply enrichers
  ├─ apply filters
  └─ List.iter (fun sink -> sink.emit_fn event) sinks  ← Bypasses Composite_sink
                                                              ↓
Composite_sink.emit (for external use only) ──────────────────────→ Per-sink filtering
```

## Solution

Consolidate all sink emission through `Composite_sink.emit`, which becomes the single source of truth for:
- Per-sink level filtering
- Sink iteration
- Error handling during emission

### Target Flow
```
Logger.write
  ├─ is_enabled check (fast path)
  ├─ create Log_event
  ├─ apply enrichers
  ├─ apply filters
  └─ Composite_sink.emit t.sinks event  ← Single entry point
                                              ↓
                                    Per-sink filtering (one place)
```

## Implementation Steps

### Step 1: Audit Current Filtering Locations

Identify all places where per-sink filtering occurs:

1. `Configuration.add_sink` (lines 40-55) - wraps emit_fn with level check
2. `Configuration.write_to` (lines 93-121) - wraps emit_fn with level check  
3. `Composite_sink.emit` (lines 12-20) - filters but is NOT called by Logger

### Step 2: Simplify Composite_sink

**File:** `lib/composite_sink.ml`

Remove the `min_level` field from `sink_fn` type since filtering will happen at the Configuration level:

```ocaml
(* BEFORE *)
type sink_fn =
  { emit_fn: Log_event.t -> unit
  ; flush_fn: unit -> unit
  ; close_fn: unit -> unit
  ; min_level: Level.t option }

(* AFTER *)
type sink_fn =
  { emit_fn: Log_event.t -> unit
  ; flush_fn: unit -> unit
  ; close_fn: unit -> unit }
```

Update `Composite_sink.emit` to simply iterate:

```ocaml
let emit t event =
  List.iter (fun sink -> sink.emit_fn event) t
```

### Step 3: Update Configuration to Use Centralized Filtering

**File:** `lib/configuration.ml`

Modify `add_sink` to NOT wrap the emit_fn, but store the min_level separately:

```ocaml
type sink_config =
  { sink_fn: Composite_sink.sink_fn
  ; min_level: Level.t option }

type t =
  { min_level: Level.t
  ; sinks: sink_config list  (* Changed from sink_fn list *)
  ; ... }

let add_sink ?min_level ~create ~emit ~flush ~close config =
  let sink = create () in
  let sink_fn =
    { Composite_sink.emit_fn= (fun event -> emit sink event)
    ; flush_fn= (fun () -> flush sink)
    ; close_fn= (fun () -> close sink) }
  in
  {config with sinks= {sink_fn; min_level} :: config.sinks}
```

### Step 4: Create Filtering Composite_sink

**File:** `lib/composite_sink.ml`

Add a new function that handles per-sink filtering:

```ocaml
type 'a sink_with_filter =
  { sink: 'a
  ; min_level: Level.t option }

let emit_filtered sinks event =
  let event_level = Log_event.get_level event in
  List.iter
    (fun {sink; min_level} ->
      match min_level with
      | Some min_lvl when Level.compare event_level min_lvl < 0 ->
          () (* Skip - event level too low *)
      | _ -> sink.emit_fn event)
    sinks
```

### Step 5: Update Logger to Use Composite_sink

**File:** `lib/logger.ml`

Change the logger type to store sinks with their filter levels:

```ocaml
type logger_impl =
  { min_level: Level.t
  ; sinks: (Composite_sink.sink_fn * Level.t option) list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: (Log_event.t -> bool) list
  ; context_properties: (string * Yojson.Safe.t) list
  ; source: string option }
```

Update `write` to use centralized filtering:

```ocaml
let write t ?exn level message_template properties =
  if not (is_enabled t level) then
    ()
  else
    let event = ... in  (* existing event creation *)
    let event = apply_enrichers t event in
    let event = add_context_properties t event in
    if not (passes_filters t event) then
      ()
    else
      (* Use centralized filtering emission *)
      List.iter
        (fun (sink_fn, min_level) ->
          match min_level with
          | Some min_lvl when Level.compare level min_lvl < 0 -> ()
          | _ -> sink_fn.Composite_sink.emit_fn event)
        t.sinks
```

### Step 6: Update Configuration.create_logger

**File:** `lib/configuration.ml`

Update to pass sinks with their filter levels:

```ocaml
let create_logger config =
  let sinks_with_levels =
    List.map
      (fun (sc : sink_config) -> (sc.sink_fn, sc.min_level))
      config.sinks
  in
  let logger = Logger.create ~min_level:config.min_level ~sinks:sinks_with_levels in
  ...
```

### Step 7: Update Tests

**Files:** `test/test_logger.ml`, `test/test_sinks.ml`, `test/test_configuration.ml`

Update all manual `sink_fn` record creations to remove `min_level` field:

```ocaml
(* BEFORE *)
{ Composite_sink.emit_fn= ...
; flush_fn= ...
; close_fn= ...
; min_level= None }

(* AFTER *)
{ Composite_sink.emit_fn= ...
; flush_fn= ...
; close_fn= ... }
```

### Step 8: Update Examples

**Files:** `examples/*.ml`, `benchmarks/benchmark.ml`

Same changes as tests - remove `min_level` field from manual sink_fn creation.

### Step 9: Update Lwt and Eio Packages

**Files:** `message-templates-lwt/lib/*.ml`, `message-templates-eio/lib/*.ml`

Update their sink types to match the new core library types.

## Testing Strategy

1. **Unit Tests**: Verify filtering still works correctly
   - Events below sink min_level are not emitted
   - Events at/above sink min_level are emitted
   - Global min_level filtering still works

2. **Integration Tests**: 
   - Multiple sinks with different min_levels
   - Ensure no double-filtering (performance regression)

3. **Regression Tests**:
   - All existing tests should pass without behavior changes

## Migration Guide

### For Library Users

**Before:**
```ocaml
let sink_fn =
  { Composite_sink.emit_fn= my_emit
  ; flush_fn= my_flush
  ; close_fn= my_close
  ; min_level= Some Level.Warning }
```

**After:**
```ocaml
let sink_fn =
  { Composite_sink.emit_fn= my_emit
  ; flush_fn= my_flush
  ; close_fn= my_close }
(* min_level now passed separately to Logger.create *)
```

### Breaking Changes

- `Composite_sink.sink_fn` loses `min_level` field
- `Logger.create` signature changes to accept `(sink_fn * Level.t option) list`

## Success Criteria

- [ ] All existing tests pass
- [ ] No performance regression (benchmark before/after)
- [ ] Code duplication eliminated (filtering only in one place)
- [ ] Lwt and Eio packages updated
- [ ] Documentation updated

## Related Files

- `lib/logger.ml`
- `lib/logger.mli`
- `lib/composite_sink.ml`
- `lib/composite_sink.mli`
- `lib/configuration.ml`
- `test/test_logger.ml`
- `test/test_sinks.ml`
- `examples/*.ml`
- `benchmarks/benchmark.ml`
- `message-templates-lwt/lib/*.ml`
- `message-templates-eio/lib/*.ml`
