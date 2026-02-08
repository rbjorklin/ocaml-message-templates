# Plan 7: Add Sink Pipeline Abstraction

## Status
**Priority:** LOW  
**Estimated Effort:** 4-6 hours  
**Risk Level:** Low (additive feature)

## Problem Statement

Currently, composing sinks requires manual wrapping and boilerplate:

```ocaml
(* Manual composition - error-prone and verbose *)
let my_sink =
  let base_sink = Console_sink.create () in
  let emit_fn event =
    if Filter.matches event then
      let enriched_event = Enricher.add_timestamp event in
      Console_sink.emit base_sink enriched_event
  in
  { Composite_sink.emit_fn
  ; flush_fn= (fun () -> Console_sink.flush base_sink)
  ; close_fn= (fun () -> Console_sink.close base_sink)
  ; min_level= Some Level.Info }
```

### Issues

1. **No Composable Primitives**: Can't easily chain transforms
2. **Inconsistent Patterns**: Each user invents their own composition style
3. **No Reusable Middleware**: Can't share filters, transformers, metrics
4. **Type Unsafe**: Easy to forget flush/close in wrapper

## Solution

Create a declarative pipeline API:

```ocaml
let pipeline =
  Pipeline.(
    source ()
    |> filter (Filter.level_filter Level.Info)
    |> transform (Enricher.add_timestamp)
    |> transform (Enricher.add_correlation_id)
    |> tee (Console_sink.create ())  (* Branch to console *)
    |> to_sink (File_sink.create "app.log")
  )
```

## Implementation Steps

### Step 1: Define Pipeline Types

**File:** `lib/pipeline.mli`

```ocaml
(** Composable sink pipelines

    Pipelines allow declarative composition of filters, transformations,
    and multiple output sinks.
*)

(** A stage in the pipeline that processes events *)
type 'a stage

(** Pipeline builder for fluent composition *)
module type BUILDER = sig
  type t
  
  (** Start a pipeline from a source *)
  val source : unit -> t
  
  (** Add a filter stage *)
  val filter : Filter.t -> t -> t
  
  (** Add a transformation stage *)
  val transform : (Log_event.t -> Log_event.t) -> t -> t
  
  (** Tee to another sink (events pass through to both) *)
  val tee : Sink.sink -> t -> t
  
  (** Send to final sink *)
  val to_sink : Sink.sink -> t -> Composite_sink.sink_fn
end

(** Simple sequential pipeline *)
module Sequential : BUILDER

(** Async pipeline with backpressure *)
module Async : sig
  include BUILDER
  
  (** Add async buffer with overflow handling *)
  val buffer : 
    ?max_size:int -> 
    ?overflow:[Drop | Block | Error] -> 
    t -> t
  
  (** Add batching stage *)
  val batch : 
    ?max_batch_size:int ->
    ?max_latency_ms:int ->
    t -> t
end
```

### Step 2: Implement Sequential Pipeline

**File:** `lib/pipeline.ml`

```ocaml
type stage = 
  | Filter of Filter.t
  | Transform of (Log_event.t -> Log_event.t)
  | Tee of Sink.sink
  | Sink of Sink.sink

module Sequential = struct
  type t = stage list

  let source () = []

  let filter f stages = Filter f :: stages

  let transform t stages = Transform t :: stages

  let tee sink stages = Tee sink :: stages

  let to_sink sink stages = 
    let stages = List.rev (Sink sink :: stages) in
    
    let emit_fn event =
      let rec process = function
        | [] -> ()
        | Filter f :: rest ->
            if f event then process rest else ()
        | Transform t :: rest ->
            process rest (t event)
        | Tee sink :: rest ->
            Sink.emit sink event;
            process rest event
        | Sink sink :: _ ->
            Sink.emit sink event
      in
      process stages event
    in
    
    let flush_fn () =
      List.iter (function
        | Tee sink | Sink sink -> Sink.flush sink
        | _ -> ()
      ) stages
    in
    
    let close_fn () =
      List.iter (function
        | Tee sink | Sink sink -> Sink.close sink
        | _ -> ()
      ) stages
    in
    
    { Composite_sink.emit_fn
    ; flush_fn
    ; close_fn }
end
```

### Step 3: Implement Async Pipeline

```ocaml
module Async = struct
  type buffer_config =
    { max_size: int
    ; overflow: [`Drop | `Block | `Error] }

  type batch_config =
    { max_size: int
    ; max_latency_ms: int }

  type stage = 
    | Filter of Filter.t
    | Transform of (Log_event.t -> Log_event.t)
    | Buffer of buffer_config
    | Batch of batch_config
    | Tee of Sink.sink
    | Sink of Sink.sink

  type t = stage list

  let source () = []
  let filter f stages = Filter f :: stages
  let transform t stages = Transform t :: stages

  let buffer ?(max_size=1000) ?(overflow=`Drop) stages =
    Buffer {max_size; overflow} :: stages

  let batch ?(max_batch_size=100) ?(max_latency_ms=100) stages =
    Batch {max_size=max_batch_size; max_latency_ms} :: stages

  let tee sink stages = Tee sink :: stages

  let to_sink sink stages =
    let stages = List.rev (Sink sink :: stages) in
    
    (* Build a chain of processing stages *)
    let build_chain stages =
      let rec build = function
        | [] -> fun event -> Sink.emit sink event
        | Filter f :: rest ->
            let next = build rest in
            fun event -> if f event then next event else ()
        | Transform t :: rest ->
            let next = build rest in
            fun event -> next (t event)
        | Buffer config :: rest ->
            let next = build rest in
            let queue = Queue.create () in
            let lock = Mutex.create () in
            let not_full = Condition.create () in
            let not_empty = Condition.create () in
            
            (* Start background processor *)
            let _thread = Thread.create (fun () ->
              while true do
                let events = Mutex.lock lock;
                  let rec drain acc =
                    if Queue.is_empty queue then
                      (Mutex.unlock lock; List.rev acc)
                    else
                      let ev = Queue.take queue in
                      if List.length acc < 100 then
                        drain (ev :: acc)
                      else
                        (Mutex.unlock lock; List.rev acc)
                  in
                  drain []
                in
                List.iter next events
              done
            ) () in
            
            fun event ->
              Mutex.lock lock;
              if Queue.length queue >= config.max_size then
                match config.overflow with
                | `Drop -> Mutex.unlock lock
                | `Block ->
                    while Queue.length queue >= config.max_size do
                      Condition.wait not_full lock
                    done;
                    Queue.add event queue;
                    Condition.signal not_empty;
                    Mutex.unlock lock
                | `Error ->
                    Mutex.unlock lock;
                    raise (Failure "Buffer overflow")
              else (
                Queue.add event queue;
                Condition.signal not_empty;
                Mutex.unlock lock
              )
        | Tee tee_sink :: rest ->
            let next = build rest in
            fun event ->
              Sink.emit tee_sink event;
              next event
        | _ -> failwith "Invalid stage order"
      in
      build stages
    in
    
    let emit_fn = build_chain stages in
    
    let flush_fn () =
      List.iter (function
        | Tee s | Sink s -> Sink.flush s
        | _ -> ()
      ) stages
    in
    
    let close_fn () =
      List.iter (function
        | Tee s | Sink s -> Sink.close s
        | _ -> ()
      ) stages
    in
    
    { Composite_sink.emit_fn=emit_fn
    ; flush_fn
    ; close_fn }
end
```

### Step 4: Add Convenience Pipeline Builders

**File:** `lib/pipeline.mli` (additions)

```ocaml
(** Pre-built pipeline patterns *)

(** Standard production pipeline:
    - Filter by level
    - Add timestamps
    - Output to console and file *)
val production_pipeline :
  min_level:Level.t ->
  log_file:string ->
  Composite_sink.sink_fn

(** Debug pipeline: everything to console with colors *)
val debug_pipeline : unit -> Composite_sink.sink_fn

(** Distributed pipeline with correlation IDs and JSON output *)
val distributed_pipeline :
  service_name:string ->
  log_file:string ->
  Composite_sink.sink_fn
```

**File:** `lib/pipeline.ml` (additions)

```ocaml
let production_pipeline ~min_level ~log_file =
  Sequential.(
    source ()
    |> filter (Filter.level_filter min_level)
    |> transform (fun event ->
        Log_event.create
          ~timestamp:(Log_event.get_timestamp event)
          ~level:(Log_event.get_level event)
          ~message_template:(Log_event.get_message_template event)
          ~rendered_message:(Log_event.get_rendered_message event)
          ~properties:(Log_event.get_properties event)
          ?exception_info:(Log_event.get_exception event)
          ?correlation_id:(Log_event.get_correlation_id event)
          ())
    |> tee (Console_sink.create ~colors:true ())
    |> to_sink (File_sink.create log_file)
  )

let debug_pipeline () =
  Sequential.(
    source ()
    |> filter (Filter.level_filter Level.Debug)
    |> to_sink (Console_sink.create ~colors:true ())
  )

let distributed_pipeline ~service_name ~log_file =
  Sequential.(
    source ()
    |> transform (fun event ->
        let props = ("Service", `String service_name) :: 
                    Log_event.get_properties event in
        Log_event.create
          ~timestamp:(Log_event.get_timestamp event)
          ~level:(Log_event.get_level event)
          ~message_template:(Log_event.get_message_template event)
          ~rendered_message:(Log_event.get_rendered_message event)
          ~properties:props
          ?exception_info:(Log_event.get_exception event)
          ?correlation_id:(Log_event.get_correlation_id event)
          ())
    |> to_sink (File_sink.create ~rolling:File_sink.Daily log_file)
  )
```

### Step 5: Add Pipeline Metrics

```ocaml
(** Metrics-collecting pipeline wrapper *)
module Metrics = struct
  type t =
    { inner: Composite_sink.sink_fn
    ; metrics: Metrics.t
    ; sink_id: string }

  let wrap ~metrics ~sink_id inner =
    let emit_fn event =
      let start = Unix.gettimeofday () in
      inner.Composite_sink.emit_fn event;
      let latency = (Unix.gettimeofday () -. start) *. 1_000_000.0 in
      Metrics.record_event metrics ~sink_id ~latency_us:latency
    in
    
    { inner with Composite_sink.emit_fn }
end
```

### Step 6: Update Configuration to Use Pipelines

**File:** `lib/configuration.ml` (add pipeline support)

```ocaml
val with_pipeline : Pipeline.Sequential.t -> t -> t

let with_pipeline pipeline config =
  let sink_fn = Pipeline.Sequential.to_sink pipeline in
  {config with sinks= {sink_fn; min_level=None} :: config.sinks}
```

## Usage Examples

### Example 1: Simple Pipeline

```ocaml
open Message_templates
open Pipeline.Sequential

let my_pipeline =
  source ()
  |> filter (Filter.level_filter Level.Info)
  |> transform (Enricher.add_property "App" (`String "MyApp"))
  |> to_sink (Console_sink.create ~colors:true ())

let logger =
  Configuration.create ()
  |> Configuration.with_pipeline my_pipeline
  |> Configuration.create_logger
```

### Example 2: Branching Pipeline

```ocaml
let pipeline =
  Pipeline.Sequential.(
    source ()
    |> filter (Filter.level_filter Level.Warning)
    |> tee (Console_sink.create ~colors:true ())  (* All warnings+ to console *)
    |> filter (Filter.level_filter Level.Error)   (* Only errors to file *)
    |> transform (Enricher.add_stack_trace)
    |> to_sink (File_sink.create "/var/log/errors.log")
  )
```

### Example 3: Async Pipeline

```ocaml
let async_pipeline =
  Pipeline.Async.(
    source ()
    |> filter (Filter.level_filter Level.Info)
    |> buffer ~max_size:10000 ~overflow:`Drop
    |> batch ~max_batch_size:100 ~max_latency_ms:100
    |> to_sink (Network_sink.create "logs.example.com:514")
  )
```

## Testing Strategy

### 1. Unit Tests

```ocaml
let test_filter_stage () =
  let events = ref [] in
  let sink = create_capture_sink events in
  
  let pipeline =
    Pipeline.Sequential.(
      source ()
      |> filter (fun event -> Log_event.get_level event = Level.Error)
      |> to_sink sink
    )
  in
  
  (* Send warning - should be filtered *)
  let warning = create_event Level.Warning in
  pipeline.Composite_sink.emit_fn warning;
  check int "warning filtered" 0 (List.length !events);
  
  (* Send error - should pass *)
  let error = create_event Level.Error in
  pipeline.Composite_sink.emit_fn error;
  check int "error passed" 1 (List.length !events)

let test_tee_stage () =
  let events1 = ref [] in
  let events2 = ref [] in
  let sink1 = create_capture_sink events1 in
  let sink2 = create_capture_sink events2 in
  
  let pipeline =
    Pipeline.Sequential.(
      source ()
      |> tee sink1
      |> to_sink sink2
    )
  in
  
  let event = create_event Level.Info in
  pipeline.Composite_sink.emit_fn event;
  
  check int "tee to sink1" 1 (List.length !events1);
  check int "passed to sink2" 1 (List.length !events2)
```

### 2. Property-Based Tests

```ocaml
let test_pipeline_composition_associativity () =
  (* (a |> b) |> c should equal a |> (b |> c) *)
  QCheck.Test.make ~name:"composition_associativity" ~count:100
    (QCheck.triple filter_gen transform_gen filter_gen)
    (fun (f1, t, f2) ->
      let events = ref [] in
      let sink = create_capture_sink events in
      
      let pipeline1 =
        Pipeline.Sequential.(
          source ()
          |> filter f1
          |> filter f2
          |> to_sink sink
        )
      in
      
      let pipeline2 =
        Pipeline.Sequential.(
          source ()
          |> filter f2
          |> filter f1
          |> to_sink sink
        )
      in
      
      (* Order matters for filters, but both should be valid *)
      true)
```

## Migration Guide

### For Library Users

**Before (manual composition):**
```ocaml
let emit_fn event =
  if event.level >= Level.Info then
    let event = add_timestamp event in
    Console_sink.emit console event;
    File_sink.emit file event
```

**After (pipeline):**
```ocaml
let pipeline =
  Pipeline.Sequential.(
    source ()
    |> filter (Filter.level_filter Level.Info)
    |> transform add_timestamp
    |> tee console
    |> to_sink file
  )
```

### Breaking Changes

None - this is a purely additive feature.

## Success Criteria

- [ ] Pipeline module created with Sequential and Async builders
- [ ] Filter, Transform, Tee, and Sink stages implemented
- [ ] Pre-built pipeline patterns provided
- [ ] All stages tested individually
- [ ] Pipeline composition tested
- [ ] Documentation with examples
- [ ] Performance comparable to manual composition

## Related Files

- `lib/pipeline.ml` (new)
- `lib/pipeline.mli` (new)
- `lib/configuration.ml` (add with_pipeline)
- `test/test_pipeline.ml` (new)
- `examples/pipeline_example.ml` (new)

## Notes

- Pipeline abstraction is optional - users can still use manual composition
- Async pipeline is complex - consider implementing in phases
- Consider adding visualization/debugging tools for pipelines
- Could integrate with tracing/metrics systems for observability
