# Plan 4: Extract Shared Logger Core to Eliminate Duplication

## Status
**Priority:** MEDIUM  
**Estimated Effort:** 6-8 hours  
**Risk Level:** Medium (touches multiple packages)

## Problem Statement

The Lwt and Eio packages (`message-templates-lwt` and `message-templates-eio`) duplicate significant amounts of code from the core logger implementation:

### Duplicated Code Patterns

1. **Logger record type definitions** (~20 lines each)
2. **`add_context_properties` function** (~25 lines) - identical logic
3. **`apply_enrichers` function** (~5 lines) - identical
4. **`passes_filters` function** (~5 lines) - identical
5. **Level comparison logic** (`is_enabled`) - identical
6. **Event creation and enrichment pipeline** (~30 lines in `write`)

### Current State

```ocaml
(* In lib/logger.ml *)
type logger_impl =
  { min_level: Level.t
  ; sinks: Composite_sink.sink_fn list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: (Log_event.t -> bool) list
  ; context_properties: (string * Yojson.Safe.t) list
  ; source: string option }

(* In message-templates-lwt/lib/lwt_logger.ml *)
type t =
  { min_level: Level.t
  ; sinks: Lwt_sink.sink_fn list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: (Log_event.t -> bool) list
  ; context_properties: (string * Yojson.Safe.t) list
  ; source: string option }

(* In message-templates-eio/lib/eio_logger.ml *)
type t =
  { min_level: Level.t
  ; sinks: Eio_sink.sink_fn list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: (Log_event.t -> bool) list
  ; context_properties: (string * Yojson.Safe.t) list
  ; source: string option
  ; sw: Eio.Switch.t option }
```

**Only differences:**
- `sinks` field has different sink_fn types
- Eio logger has extra `sw` field

### Functions with Identical Implementations

| Function | Lines | Duplicated In |
|----------|-------|---------------|
| `is_enabled` | 1 | logger.ml, lwt_logger.ml, eio_logger.ml |
| `passes_filters` | 1 | logger.ml, lwt_logger.ml, eio_logger.ml |
| `apply_enrichers` | 3 | logger.ml, lwt_logger.ml, eio_logger.ml |
| `add_context_properties` | 25 | logger.ml, lwt_logger.ml, eio_logger.ml |

## Solution

Extract shared logger logic into a functor-based `Logger_core` module that can be instantiated for different sink types and effect systems.

## Implementation Steps

### Step 1: Define Logger_core Signature

**File:** `lib/logger_core.mli`

```ocaml
(** Core logger functionality shared across sync, Lwt, and Eio implementations *)

module type SINK = sig
  type 'a t
  val emit : 'a t -> Log_event.t -> 'a
  val flush : 'a t -> 'a unit
  val close : 'a t -> 'a unit
end

module type MONAD = sig
  type 'a t
  val return : 'a -> 'a t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
  val iter_p : ('a -> unit t) -> 'a list -> unit t
end

module type LOGGER = sig
  type 'a sink_fn
  type 'a t
  
  val create :
    min_level:Level.t ->
    sinks:'a sink_fn list ->
    'a t
  
  val write :
    'a t ->
    ?exn:exn ->
    Level.t ->
    string ->
    (string * Yojson.Safe.t) list ->
    unit
  
  val is_enabled : 'a t -> Level.t -> bool
  val verbose : 'a t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val debug : 'a t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val information : 'a t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val warning : 'a t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val error : 'a t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val fatal : 'a t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val for_context : 'a t -> string -> Yojson.Safe.t -> 'a t
  val with_enricher : 'a t -> (Log_event.t -> Log_event.t) -> 'a t
  val for_source : 'a t -> string -> 'a t
  val flush : 'a t -> unit
  val close : 'a t -> unit
end

module Make (M : MONAD) (S : SINK with type 'a t = M.t) : LOGGER
```

### Step 2: Implement Logger_core Functor

**File:** `lib/logger_core.ml`

```ocaml
module type SINK = sig
  type 'a t
  val emit : 'a t -> Log_event.t -> 'a
  val flush : 'a t -> 'a unit
  val close : 'a t -> 'a unit
end

module type MONAD = sig
  type 'a t
  val return : 'a -> 'a t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
  val iter_p : ('a -> unit t) -> 'a list -> unit t
end

module Make (M : MONAD) (S : SINK with type 'a t = M.t) = struct
  type 'a sink_fn = 'a S.t

  type 'a t =
    { min_level: Level.t
    ; sinks: 'a sink_fn list
    ; enrichers: (Log_event.t -> Log_event.t) list
    ; filters: (Log_event.t -> bool) list
    ; context_properties: (string * Yojson.Safe.t) list
    ; source: string option }

  (* These functions are now SHARED *)
  
  let is_enabled t level = Level.compare level t.min_level >= 0

  let passes_filters t event =
    List.for_all (fun filter -> filter event) t.filters

  let apply_enrichers t event =
    List.fold_left (fun ev enricher -> enricher ev) event t.enrichers

  let add_context_properties t event =
    let ambient_props = Log_context.current_properties () in
    let correlation_id = Log_context.get_correlation_id () in
    if ambient_props = [] && t.context_properties = [] && correlation_id = None then
      event
    else
      let current_props = Log_event.get_properties event in
      let new_props = ambient_props @ t.context_properties @ current_props in
      Log_event.create
        ~timestamp:(Log_event.get_timestamp event)
        ~level:(Log_event.get_level event)
        ~message_template:(Log_event.get_message_template event)
        ~rendered_message:(Log_event.get_rendered_message event)
        ~properties:new_props
        ?exception_info:(Log_event.get_exception event)
        ?correlation_id:
          (match correlation_id with
           | None -> Log_event.get_correlation_id event
           | Some _ -> correlation_id)
        ()

  let write t ?exn level message_template properties =
    if not (is_enabled t level) then
      M.return ()
    else
      let rendered_message =
        Runtime_helpers.render_template message_template properties
      in
      let correlation_id = Log_context.get_correlation_id () in
      let event =
        Log_event.create ~level ~message_template ~rendered_message ~properties
          ?exception_info:exn ?correlation_id ()
      in
      let event = apply_enrichers t event in
      let event = add_context_properties t event in
      if not (passes_filters t event) then
        M.return ()
      else
        M.iter_p (fun sink -> S.emit sink event) t.sinks

  (* Level-specific convenience methods *)
  let verbose t ?exn message properties =
    write t ?exn Level.Verbose message properties

  let debug t ?exn message properties =
    write t ?exn Level.Debug message properties

  let information t ?exn message properties =
    write t ?exn Level.Information message properties

  let warning t ?exn message properties =
    write t ?exn Level.Warning message properties

  let error t ?exn message properties =
    write t ?exn Level.Error message properties

  let fatal t ?exn message properties =
    write t ?exn Level.Fatal message properties

  (* Context and enrichment *)
  let for_context t name value =
    {t with context_properties= (name, value) :: t.context_properties}

  let with_enricher t enricher =
    {t with enrichers= enricher :: t.enrichers}

  let for_source t source_name =
    {t with source= Some source_name}

  (* Lifecycle *)
  let flush t = M.iter_p S.flush t.sinks

  let close t = M.iter_p S.close t.sinks
end
```

### Step 3: Define Identity Monad for Synchronous Logger

**File:** `lib/logger_core.ml` (continued)

```ocaml
(** Identity monad for synchronous operations *)
module Identity = struct
  type 'a t = 'a
  let return x = x
  let bind x f = f x
  let iter_p f lst = List.iter f lst; ()
end
```

### Step 4: Refactor Core Logger to Use Logger_core

**File:** `lib/logger.ml` (simplified)

```ocaml
open Logger_core

(* Define synchronous sink type *)
module Sync_sink = struct
  type 'a t = Composite_sink.sink_fn
  let emit sink event = sink.Composite_sink.emit_fn event
  let flush sink = sink.Composite_sink.flush_fn ()
  let close sink = sink.Composite_sink.close_fn ()
end

(* Instantiate the logger *)
module Sync_logger = Make(Identity)(Sync_sink)

(* Re-export types and functions *)
type t = Identity.t Sync_logger.t

let create ~min_level ~sinks =
  Sync_logger.create ~min_level ~sinks

let write t ?exn level message properties =
  Sync_logger.write t ?exn level message properties

let is_enabled = Sync_logger.is_enabled
let verbose = Sync_logger.verbose
let debug = Sync_logger.debug
let information = Sync_logger.information
let warning = Sync_logger.warning
let error = Sync_logger.error
let fatal = Sync_logger.fatal
let for_context = Sync_logger.for_context
let with_enricher = Sync_logger.with_enricher
let for_source = Sync_logger.for_source
let flush = Sync_logger.flush
let close = Sync_logger.close

(* Additional helpers not in core *)
let add_property t name value = for_context t name value

let add_min_level_filter t min_level =
  let filter event = Level.compare (Log_event.get_level event) min_level >= 0 in
  with_enricher t (fun event -> event)  (* Actually need to modify filters *)
  (* Note: This reveals that filters shouldn't be in enrichers list *)
  (* Will need to adjust the core design *)
```

### Step 5: Refactor Lwt Logger

**File:** `message-templates-lwt/lib/lwt_logger.ml`

```ocaml
open Message_templates
open Lwt.Syntax

(* Define Lwt sink type *)
module Lwt_sink_impl = struct
  type 'a t = Lwt_sink.sink_fn
  let emit sink event = sink.Lwt_sink.emit_fn event
  let flush sink = sink.Lwt_sink.flush_fn ()
  let close sink = sink.Lwt_sink.close_fn ()
end

(* Define Lwt monad *)
module Lwt_monad = struct
  type 'a t = 'a Lwt.t
  let return = Lwt.return
  let bind = Lwt.bind
  let iter_p = Lwt_list.iter_p
end

(* Instantiate the logger *)
module Lwt_logger = Message_templates.Logger_core.Make(Lwt_monad)(Lwt_sink_impl)

type t = Lwt_logger.t

let create ~min_level ~sinks = Lwt_logger.create ~min_level ~sinks
let write = Lwt_logger.write
let is_enabled = Lwt_logger.is_enabled
let verbose = Lwt_logger.verbose
let debug = Lwt_logger.debug
let information = Lwt_logger.information
let warning = Lwt_logger.warning
let error = Lwt_logger.error
let fatal = Lwt_logger.fatal
let for_context = Lwt_logger.for_context
let with_enricher = Lwt_logger.with_enricher
let for_source = Lwt_logger.for_source
let flush = Lwt_logger.flush
let close = Lwt_logger.close
```

### Step 6: Refactor Eio Logger

**File:** `message-templates-eio/lib/eio_logger.ml`

```ocaml
open Message_templates

(* Eio uses direct style, similar to Identity but with effect awareness *)
module Eio_monad = struct
  type 'a t = 'a
  let return x = x
  let bind x f = f x
  let iter_p f lst = List.iter f lst; ()
end

module Eio_sink_impl = struct
  type 'a t = Eio_sink.sink_fn
  let emit sink event = sink.Eio_sink.emit_fn event
  let flush sink = sink.Eio_sink.flush_fn ()
  let close sink = sink.Eio_sink.close_fn ()
end

module Eio_logger_core = Message_templates.Logger_core.Make(Eio_monad)(Eio_sink_impl)

type t = 
  { core: Eio_logger_core.t
  ; sw: Eio.Switch.t option }

(* Wrap core functions to add Eio-specific async support *)
let create ?sw ~min_level ~sinks () =
  { core= Eio_logger_core.create ~min_level ~sinks
  ; sw }

let write t ?exn level message properties =
  Eio_logger_core.write t.core ?exn level message properties

let write_async t ?exn level message properties =
  match t.sw with
  | Some sw ->
      Eio.Fiber.fork ~sw (fun () ->
        try write t ?exn level message properties
        with exn ->
          Printf.eprintf "Logging error: %s\n" (Printexc.to_string exn))
  | None -> write t ?exn level message properties

(* Delegate other functions to core *)
let is_enabled t = Eio_logger_core.is_enabled t.core
let verbose t ?exn msg props = Eio_logger_core.verbose t.core ?exn msg props
let debug t ?exn msg props = Eio_logger_core.debug t.core ?exn msg props
let information t ?exn msg props = Eio_logger_core.information t.core ?exn msg props
let warning t ?exn msg props = Eio_logger_core.warning t.core ?exn msg props
let error t ?exn msg props = Eio_logger_core.error t.core ?exn msg props
let fatal t ?exn msg props = Eio_logger_core.fatal t.core ?exn msg props
let for_context t name value = {t with core= Eio_logger_core.for_context t.core name value}
let with_enricher t enricher = {t with core= Eio_logger_core.with_enricher t.core enricher}
let for_source t source = {t with core= Eio_logger_core.for_source t.core source}
let flush t = Eio_logger_core.flush t.core
let close t = Eio_logger_core.close t.core
```

### Step 7: Update Build Configuration

**File:** `lib/dune`

```scheme
(library
 (public_name message-templates)
 (name message_templates)
 (libraries yojson eio angstrom ptime unix str threads)
 (modules_without_implementation sink logger_core))
```

**File:** `message-templates-lwt/lib/dune`

Update to use new core module.

### Step 8: Update Tests

All test files should continue to work as the external API remains unchanged.

## Alternative: First-Class Module Approach

If the functor approach proves too complex, use first-class modules:

```ocaml
module type LOGGER_OPS = sig
  type 'a t
  val emit : 'a t -> Log_event.t -> unit
  val flush : 'a t -> unit
  val close : 'a t -> unit
end

let create_logger (type a) (module Ops : LOGGER_OPS with type 'a t = a) 
    ~min_level ~sinks () =
  (* shared implementation using Ops.emit, etc. *)
```

## Testing Strategy

1. **API Compatibility Tests**: Ensure existing code compiles without changes
2. **Behavioral Tests**: Verify all existing tests still pass
3. **Performance Tests**: Ensure functor overhead doesn't affect benchmarks

## Migration Guide

### For Library Users

No changes required - this is purely internal refactoring.

### For Contributors

When adding new logger features:
1. Add to `Logger_core.Make` if applicable to all variants
2. Add to specific logger module (logger.ml, lwt_logger.ml, eio_logger.ml) for variant-specific features

## Success Criteria

- [ ] `Logger_core` module created with functor
- [ ] Core logger refactored to use `Logger_core`
- [ ] Lwt logger refactored to use `Logger_core`
- [ ] Eio logger refactored to use `Logger_core`
- [ ] All existing tests pass
- [ ] No performance regression
- [ ] Code duplication eliminated (measure lines of code before/after)

## Metrics to Track

| Metric | Before | After |
|--------|--------|-------|
| Lines in logger.ml | ~190 | ~40 |
| Lines in lwt_logger.ml | ~125 | ~40 |
| Lines in eio_logger.ml | ~159 | ~60 |
| Duplicate functions | 15+ | 0 |

## Related Files

- `lib/logger_core.ml` (new)
- `lib/logger_core.mli` (new)
- `lib/logger.ml`
- `message-templates-lwt/lib/lwt_logger.ml`
- `message-templates-eio/lib/eio_logger.ml`
- `lib/dune`
- `message-templates-lwt/lib/dune`
- `message-templates-eio/lib/dune`
