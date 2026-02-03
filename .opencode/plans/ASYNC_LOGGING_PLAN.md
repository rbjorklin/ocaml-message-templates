# Async Logging Support Plan: Lwt and Eio

## Executive Summary

This plan outlines how to add comprehensive async logging support to the OCaml Message Templates library using both **Lwt** (monadic concurrency) and **Eio** (effects-based concurrency). The implementation will maintain backward compatibility with the existing synchronous API while providing idiomatic async interfaces for both libraries.

## Current Architecture Analysis

### Existing Sink Interface (Synchronous)
```ocaml
module type S = sig
  type t
  val emit : t -> Log_event.t -> unit
  val flush : t -> unit
  val close : t -> unit
end
```

### Current Logger Flow
```
Application Code
       |
       v
Level Check (unit -> bool)
       |
       v
Template Expansion (PPX - returns (string * Yojson.Safe.t))
       |
       v
Context Enrichment (unit -> unit)
       |
       v
Filtering (unit -> bool)
       |
       v
Sinks (emit : unit)
```

## Proposed Architecture

### Option 1: Separate Packages (Recommended)

Create three separate packages:
1. `message-templates` - Core sync library (no changes)
2. `message-templates-lwt` - Lwt async support
3. `message-templates-eio` - Eio async support

**Advantages:**
- Users only depend on what they need
- No bloat for sync-only users
- Clean separation of concerns
- Independent versioning possible
- Follows OCaml ecosystem conventions (e.g., `cohttp` vs `cohttp-lwt` vs `cohttp-eio`)

### Option 2: Single Package with Sub-libraries

Use dune's sub-library feature:
- `message-templates` - Core
- `message-templates.lwt` - Lwt support
- `message-templates.eio` - Eio support

**Advantages:**
- Single package to install
- Unified versioning

**Disadvantages:**
- All dependencies installed even if unused
- Larger binary sizes

**Decision: Use Option 1 (Separate Packages)**

## Implementation Plan

### Phase 1: Create Core Async Abstractions

#### 1.1 Define Async Sink Signatures

Create `lib/async_sink_intf.ml` in the core library:

```ocaml
(** Async sink signatures - framework agnostic *)

module type ASYNC_SINK = sig
  type t
  type 'a promise

  val emit : t -> Log_event.t -> unit promise
  val flush : t -> unit promise
  val close : t -> unit promise
end

module type ASYNC = sig
  type 'a t
  val return : 'a -> 'a t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
  val catch : (unit -> 'a t) -> (exn -> 'a t) -> 'a t
end
```

#### 1.2 Create Functor for Async Logger

```ocaml
module Async_logger (M : ASYNC) = struct
  type t = {
    min_level: Level.t;
    sinks: (module ASYNC_SINK with type 'a promise = 'a M.t) list;
    enrichers: (Log_event.t -> Log_event.t) list;
    filters: (Log_event.t -> bool) list;
    context_properties: (string * Yojson.Safe.t) list;
  }

  let write t ?exn level message_template properties =
    if not (is_enabled t level) then
      M.return ()
    else
      (* Build event *)
      let event = create_event ... in
      (* Check filters *)
      if not (passes_filters t event) then
        M.return ()
      else
        (* Emit to all sinks concurrently *)
        let emit_to_sink sink =
          let module S = (val sink : ASYNC_SINK) in
          S.emit sink event
        in
        let promises = List.map emit_to_sink t.sinks in
        (* Wait for all *)
        fold_promises M.bind M.return promises
end
```

### Phase 2: Lwt Implementation (message-templates-lwt)

#### 2.1 Package Structure

```
message-templates-lwt/
├── lib/
│   ├── dune
│   ├── message_templates_lwt.ml
│   ├── lwt_sink.ml           # Lwt-specific sinks
│   ├── lwt_file_sink.ml      # Async file I/O
│   ├── lwt_console_sink.ml   # Async console output
│   ├── lwt_logger.ml         # Lwt logger implementation
│   └── lwt_configuration.ml  # Lwt configuration builder
├── test/
│   └── test_lwt_sinks.ml
└── examples/
    └── lwt_example.ml
```

#### 2.2 Lwt Sink Interface

```ocaml
(** Lwt sink interface *)
module type LWT_SINK = sig
  type t
  val emit : t -> Log_event.t -> unit Lwt.t
  val flush : t -> unit Lwt.t
  val close : t -> unit Lwt.t
end

(** Convert sync sink to Lwt sink *)
module Sync_to_lwt (S : Sink.S) : LWT_SINK with type t = S.t = struct
  type t = S.t

  let emit t event =
    Lwt.return (S.emit t event)

  let flush t =
    Lwt.return (S.flush t)

  let close t =
    Lwt.return (S.close t)
end
```

#### 2.3 Lwt File Sink (Non-blocking I/O)

```ocaml
module Lwt_file_sink : sig
  include LWT_SINK

  type rolling_interval = Infinite | Daily | Hourly

  val create :
    ?output_template:string ->
    ?rolling:rolling_interval ->
    string ->
    t Lwt.t
end = struct
  type t = {
    base_path: string;
    mutable current_path: string;
    mutable fd: Lwt_unix.file_descr;
    output_template: string;
    rolling: rolling_interval;
    mutable last_roll_time: Ptime.t;
    mutex: Lwt_mutex.t;  (* For thread-safe rolling *)
  }

  let emit t event =
    Lwt_mutex.with_lock t.mutex (fun () ->
      let* () = check_and_roll t event in
      let output_str = format_output t event in
      let* () = Lwt_io.write t.fd output_str in
      Lwt_io.write t.fd "\n"
    )
end
```

#### 2.4 Lwt Configuration API

```ocaml
module Configuration = struct
  type t = {
    min_level: Level.t;
    sinks: lwt_sink_config list;
    enrichers: (Log_event.t -> Log_event.t) list;
    filters: Filter.t list;
    context_properties: (string * Yojson.Safe.t) list;
    batching: batching_config option;
  }

  (** Add Lwt file sink *)
  val write_to_file :
    ?min_level:Level.t ->
    ?rolling:File_sink.rolling_interval ->
    ?output_template:string ->
    string -> t -> t

  (** Add Lwt console sink *)
  val write_to_console :
    ?min_level:Level.t ->
    ?colors:bool ->
    ?stderr_threshold:Level.t ->
    ?output_template:string ->
    unit -> t -> t

  (** Wrap with batching *)
  val with_batching :
    ?max_batch_size:int ->
    ?max_delay_ms:int ->
    t -> t

  (** Create Lwt logger *)
  val create_logger : t -> Lwt_logger.t
end
```

#### 2.5 Lwt Logger Usage

```ocaml
open Message_templates
open Message_templates_lwt

let setup_logging () =
  Configuration.create ()
  |> Configuration.minimum_level Level.Information
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.write_to_file ~rolling:Daily "app.log"
  |> Configuration.create_logger

let process_request logger req =
  let* () = Lwt_logger.information logger "Processing request {id}" ["id", `Int req.id] in
  (* async work *)
  let* result = fetch_data () in
  Lwt_logger.debug logger "Got result: {result}" ["result", `String result]
```

### Phase 3: Eio Implementation (message-templates-eio)

#### 3.1 Package Structure

```
message-templates-eio/
├── lib/
│   ├── dune
│   ├── message_templates_eio.ml
│   ├── eio_sink.ml
│   ├── eio_file_sink.ml      # Eio file operations
│   ├── eio_console_sink.ml   # Eio console output
│   ├── eio_logger.ml         # Eio logger implementation
│   └── eio_configuration.ml  # Eio configuration builder
├── test/
│   └── test_eio_sinks.ml
└── examples/
    └── eio_example.ml
```

#### 3.2 Eio Sink Interface

```ocaml
(** Eio sink interface *)
module type EIO_SINK = sig
  type t
  val emit : t -> Log_event.t -> unit
  val flush : t -> unit
  val close : t -> unit
end

(** Eio is direct-style, so we use effects for concurrency *)
module Eio_file_sink : sig
  include EIO_SINK

  val create :
    sw:Eio.Switch.t ->
    fs:#Eio.Fs.dir Eio.Path.t ->
    ?output_template:string ->
    ?rolling:rolling_interval ->
    string ->
    t
end = struct
  type t = {
    base_path: string;
    mutable current_path: string;
    mutable file: Eio.Fs.dir Eio.Path.t;
    output_template: string;
    rolling: rolling_interval;
    mutable last_roll_time: Ptime.t;
    sw: Eio.Switch.t;
    mutex: Eio.Mutex.t;
  }

  let emit t event =
    Eio.Mutex.use t.mutex (fun () ->
      check_and_roll t event;
      let output_str = format_output t event in
      Eio.Flow.write t.file (Cstruct.of_string (output_str ^ "\n"))
    )
end
```

#### 3.3 Eio Logger (Direct-Style with Fibers)

```ocaml
module Eio_logger : sig
  type t

  val create :
    sw:Eio.Switch.t ->
    min_level:Level.t ->
    sinks:(module EIO_SINK with type t = 'a) list ->
    t

  (** All methods run in current fiber, but sinks may use background fibers *)
  val write : t -> ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit

  val information : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val debug : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  (* ... etc *)

  (** Fire-and-forget logging - runs in background fiber *)
  val write_async : t -> ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit
end = struct
  type t = {
    min_level: Level.t;
    sinks: (module EIO_SINK) list;
    enrichers: (Log_event.t -> Log_event.t) list;
    filters: (Log_event.t -> bool) list;
    sw: Eio.Switch.t;
  }

  let write_async t ?exn level msg props =
    (* Spawn background fiber for logging *)
    Eio.Fiber.fork ~sw:t.sw (fun () ->
      try
        write t ?exn level msg props
      with exn ->
        (* Handle error - maybe log to stderr *)
        Printf.eprintf "Logging error: %s\n" (Printexc.to_string exn)
    )
end
```

#### 3.4 Eio Configuration API

```ocaml
module Configuration = struct
  type t = { (* similar to Lwt *) }

  (** Add Eio file sink *)
  val write_to_file :
    ?min_level:Level.t ->
    ?rolling:File_sink.rolling_interval ->
    ?output_template:string ->
    string -> t -> t

  (** Add Eio console sink *)
  val write_to_console :
    ?min_level:Level.t ->
    ?colors:bool ->
    ?stderr_threshold:Level.t ->
    ?output_template:string ->
    unit -> t -> t

  (** Enable fiber-based background logging *)
  val with_background_logging : ?buffer_size:int -> t -> t

  (** Create Eio logger - requires switch for fiber management *)
  val create_logger : sw:Eio.Switch.t -> t -> Eio_logger.t
end
```

#### 3.5 Eio Logger Usage

```ocaml
open Message_templates
open Message_templates_eio

let run ~stdout ~fs =
  Eio.Switch.run @@ fun sw ->
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Information
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.write_to_file ~rolling:Daily "app.log"
    |> Configuration.with_background_logging ~buffer_size:1000
    |> Configuration.create_logger ~sw
  in

  (* Synchronous logging - waits for completion *)
  Eio_logger.information logger "Server starting" [];

  (* Fire-and-forget logging - returns immediately *)
  Eio_logger.write_async logger "Background task started" [];

  (* In request handler *)
  let handle_request req =
    Eio_logger.information logger "Request {method} {path}"
      ["method", `String req.method; "path", `String req.path]
  in

  (* Run server *)
  Eio_net.run_server ~sw handle_request
```

### Phase 4: Batching and Buffering

#### 4.1 Batching Sink Wrapper

Both Lwt and Eio can share batching logic via a functor:

```ocaml
module Batching_sink (M : ASYNC) (S : ASYNC_SINK with type 'a promise = 'a M.t) = struct
  type t = {
    inner: S.t;
    max_batch_size: int;
    max_delay: float;
    mutable buffer: Log_event.t list;
    mutable timer: unit M.t option;
    mutex: M_mutex.t;  (* Abstract over mutex type *)
  }

  let emit t event =
    M_mutex.with_lock t.mutex (fun () ->
      t.buffer <- event :: t.buffer;
      if List.length t.buffer >= t.max_batch_size then
        flush t
      else if t.timer = None then
        (* Start timer *)
        t.timer <- Some (schedule_flush t)
    )

  let flush t =
    M_mutex.with_lock t.mutex (fun () ->
      match t.buffer with
      | [] -> M.return ()
      | events ->
          t.buffer <- [];
          t.timer <- None;
          (* Flush all events to inner sink *)
          M.fold_left
            (fun () event -> S.emit t.inner event)
            (M.return ())
            (List.rev events)
    )
end
```

### Phase 5: Integration and Testing

#### 5.1 Test Strategy

**Lwt Tests:**
```ocaml
let test_lwt_file_sink () =
  let open Lwt.Syntax in
  let* sink = Lwt_file_sink.create "test.log" in
  let event = create_test_event () in
  let* () = Lwt_file_sink.emit sink event in
  let* () = Lwt_file_sink.close sink in
  (* Verify file contents *)
  let* content = Lwt_io.with_file ~mode:Input "test.log" Lwt_io.read in
  Alcotest.(check string) "File contains log" expected content;
  Lwt.return ()
```

**Eio Tests:**
```ocaml
let test_eio_file_sink () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let fs = env#fs in
  let sink = Eio_file_sink.create ~sw ~fs "test.log" in
  let event = create_test_event () in
  Eio_file_sink.emit sink event;
  Eio_file_sink.close sink;
  (* Verify file *)
  let content = Eio.Path.load (Eio.Path.(fs / "test.log")) in
  Alcotest.(check string) "File contains log" expected content
```

#### 5.2 Performance Comparison

Create benchmarks comparing:
- Sync logging
- Lwt logging
- Eio logging
- Batched vs unbatched
- File vs console sinks

### Phase 6: Documentation

#### 6.1 API Documentation
- Full odoc comments for all modules
- Async-specific examples
- Migration guide from sync to async

#### 6.2 User Guides
- "Getting Started with Lwt Logging"
- "Getting Started with Eio Logging"
- "Choosing Between Lwt and Eio"
- "Performance Tuning for Async Logging"

## Dependencies

### message-templates-lwt
```dune
(depends
  (ocaml (>= 5.4.0))
  (message-templates (= :version))
  (lwt (>= 5.6))
  (lwt-unix (>= 5.6)))
```

### message-templates-eio
```dune
(depends
  (ocaml (>= 5.4.0))
  (message-templates (= :version))
  (eio (>= 1.0))
  (eio_main (>= 1.0)))
```

## Migration Path

### From Sync to Lwt
```ocaml
(* Before (sync) *)
let () =
  let logger = Configuration.create () |> Configuration.create_logger in
  Log.information "Starting" []

(* After (Lwt) *)
let () =
  Lwt_main.run begin
    let logger =
      Lwt_configuration.create ()
      |> Lwt_configuration.create_logger
    in
    Lwt_logger.information logger "Starting" []
  end
```

### From Sync to Eio
```ocaml
(* Before (sync) *)
let () =
  let logger = Configuration.create () |> Configuration.create_logger in
  Log.information "Starting" []

(* After (Eio) *)
let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let logger =
    Eio_configuration.create ()
    |> Eio_configuration.create_logger ~sw
  in
  Eio_logger.information logger "Starting" []
```

## Success Criteria

1. **Functionality**
   - [ ] Lwt sinks work correctly with file/console outputs
   - [ ] Eio sinks work correctly with file/console outputs
   - [ ] Batching/buffering works for both
   - [ ] Backpressure handling implemented

2. **Performance**
   - [ ] Lwt version: <20% overhead vs sync for file I/O
   - [ ] Eio version: <10% overhead vs sync for file I/O
   - [ ] Batching improves throughput by 3x+

3. **Compatibility**
   - [ ] All existing sync tests pass
   - [ ] Lwt tests pass with async behavior
   - [ ] Eio tests pass with async behavior
   - [ ] Can mix sync and async sinks (via wrappers)

4. **Documentation**
   - [ ] Complete API docs
   - [ ] Usage examples for both
   - [ ] Performance benchmarks published
   - [ ] Migration guide complete

## Timeline Estimate

- **Phase 1 (Core abstractions)**: 2-3 days
- **Phase 2 (Lwt implementation)**: 1 week
- **Phase 3 (Eio implementation)**: 1 week
- **Phase 4 (Batching)**: 3-4 days
- **Phase 5 (Testing)**: 1 week
- **Phase 6 (Documentation)**: 3-4 days

**Total**: 4-5 weeks for one developer, 2-3 weeks for two developers working in parallel

## Questions for Discussion

1. **Should we provide a compatibility layer** to make it easier to switch between Lwt and Eio?

2. **Batching defaults**: What are sensible defaults for batch size and delay?

3. **Error handling in async**: Should failed async writes be retried? Logged to stderr? Silently dropped?

4. **Resource management**: Should we provide automatic cleanup (e.g., via finalizers) or require explicit close?

5. **Metrics**: Should we expose metrics (queue depth, dropped events, etc.)?

## Notes

- The project already depends on Eio (as seen in dune-project), but this is for the core library. The async packages will extend this.
- The existing `Obj` module usage has been addressed with compile-time type conversions, so async code won't need to worry about that.
- The correlation ID support in Log_context will work seamlessly with async boundaries.
- We should consider using `Lwt_engine.set` for custom Lwt engines if users need specific async behavior.
