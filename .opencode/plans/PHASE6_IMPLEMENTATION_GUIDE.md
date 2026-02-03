# Phase 6: Implementation Guide

**Created**: February 2, 2026  
**Purpose**: Step-by-step implementation instructions for Phase 6  
**Audience**: Developer implementing Phase 6

---

## Quick Reference

### Phase 6 Goals
1. ✅ Async sink queueing with back-pressure
2. ✅ Observability metrics (throughput, latency, drops)
3. ✅ Structured shutdown and cleanup
4. ✅ Error recovery (circuit breaker, fallback)
5. ✅ Memory limits and cleanup

### Key Concepts

**Async Queueing**: Non-blocking buffer between logger and sink I/O
- Solve: Blocking I/O pauses application
- Mechanism: Mutex-protected queue, background flush thread
- Benefit: ~100x faster emit (1μs vs 4μs)

**Metrics**: Observability into logging system
- Solve: Can't detect slow sinks, drops, errors
- Mechanism: Per-sink counters (events, drops, errors, latency)
- Benefit: Operational visibility

**Shutdown**: Graceful cleanup protocol
- Solve: Lost events on exit, hanging threads
- Mechanism: Registered cleanup handlers, timeout protection
- Benefit: Zero-loss shutdown

**Circuit Breaker**: Error recovery pattern
- Solve: One broken sink breaks all logging
- Mechanism: Tracks failures, opens circuit, recovers
- Benefit: Resilient to transient failures

**Memory Limits**: Prevent queue explosion
- Solve: Unbounded queue can exhaust memory
- Mechanism: Track bytes, drop oldest under pressure
- Benefit: Predictable memory usage

---

## Phase 6 Modules to Implement

### 1. `lib/async_sink_queue.mli` (Public Interface)

```ocaml
(** Non-blocking event queue for sink batching *)

type t
(** Queued sink wrapper *)

type config = {
  max_queue_size: int;
  flush_interval_ms: int;
  batch_size: int;
  back_pressure_threshold: int;
  error_handler: exn -> unit;
}

val create : config -> Sink.t -> t
val enqueue : t -> Log_event.t -> unit
val get_queue_depth : t -> int
val flush : t -> unit
val close : t -> unit
val is_alive : t -> bool
```

**Key Design Decisions**:
- Queue is FIFO (preserve log order)
- Non-blocking: drops oldest if full (vs blocking)
- Background thread flushes periodically
- Error handler called on sink failures

### 2. `lib/async_sink_queue.ml` (Implementation)

**Algorithm**:
```
Initial state:
  - Queue: empty circular buffer [None, None, None, None, None]
  - Head: 0, Tail: 0
  - Lock: Mutex

Enqueue operation (non-blocking):
  1. Lock the mutex
  2. If queue full:
       - Drop oldest: move head forward
       - Increment drop counter
  3. Add event at tail
  4. Increment tail
  5. If depth > back_pressure_threshold: log warning
  6. Unlock

Background flush thread:
  Every N milliseconds:
  1. Lock the mutex
  2. If queue has events:
       - Batch: take up to batch_size events
       - Unlock
       - Emit to sink (without lock)
       - Lock again if more to do
  3. Unlock

Close operation:
  1. Stop background thread
  2. Lock mutex
  3. Flush all remaining events
  4. Unlock
  5. Close sink
```

**Data Structure**:
```ocaml
type t = {
  mutable events: Log_event.t option array;  (* Circular buffer *)
  mutable head: int;        (* Read position *)
  mutable tail: int;        (* Write position *)
  max_size: int;
  config: config;
  lock: Mutex.t;
  mutable background_thread: Thread.t option;
  mutable shutdown: bool;
  mutable stats: stats;
}

and stats = {
  mutable total_enqueued: int;
  mutable total_dropped: int;
  mutable total_emitted: int;
  mutable total_errors: int;
}
```

**Background Thread Implementation**:
```ocaml
let start_background_flush t =
  let thread = Thread.create (fun () ->
    while not t.shutdown do
      Thread.delay (float_of_int t.config.flush_interval_ms /. 1000.0);
      try flush t
      with exn ->
        t.config.error_handler exn;
        incr t.stats.total_errors
    done
  ) () in
  t.background_thread <- Some thread
```

### 3. `lib/metrics.mli` (Public Interface)

```ocaml
(** Observability metrics for logging system *)

type sink_metrics = {
  sink_id: string;
  events_total: int;
  events_dropped: int;
  events_failed: int;
  bytes_written: int;
  last_error: (exn * float) option;  (* error * timestamp *)
  latency_p50_us: float;
  latency_p95_us: float;
}

type t

val create : unit -> t
val record_event : t -> sink_id:string -> latency_us:float -> unit
val record_drop : t -> sink_id:string -> unit
val record_error : t -> sink_id:string -> exn -> unit
val get_sink_metrics : t -> string -> sink_metrics option
val get_all_metrics : t -> sink_metrics list
val reset : t -> unit
val to_json : t -> Yojson.Safe.t
```

**Data Structure**:
```ocaml
type t = {
  mutable sinks: (string, sink_data) Hashtbl.t;
  lock: Mutex.t;
}

and sink_data = {
  mutable events_total: int;
  mutable events_dropped: int;
  mutable events_failed: int;
  mutable bytes_written: int;
  mutable last_error: (exn * float) option;
  latencies: float Queue.t;  (* Keep last 1000 *)
  mutable p50: float;
  mutable p95: float;
}
```

**Latency Calculation**:
```ocaml
let update_percentiles latencies =
  let arr = Queue.fold (fun acc x -> x :: acc) [] latencies |> Array.of_list in
  Array.sort Float.compare arr;
  let p50_idx = Array.length arr / 2 in
  let p95_idx = (Array.length arr * 95) / 100 in
  (arr.(p50_idx), arr.(p95_idx))
```

### 4. `lib/shutdown.mli` (Public Interface)

```ocaml
(** Structured shutdown protocol *)

type shutdown_strategy =
  | Immediate
  | Flush_pending
  | Graceful of float  (* timeout in seconds *)

type t

val create : unit -> t
val register : t -> (unit -> unit) -> unit
val execute : t -> shutdown_strategy -> unit
val add_timeout : t -> float -> unit
val is_shutdown : t -> bool
```

**Data Structure**:
```ocaml
type t = {
  mutable handlers: (unit -> unit) list;
  lock: Mutex.t;
  mutable shutdown_complete: bool;
  mutable timeout: float option;
}
```

**Shutdown Phases**:
```ocaml
let execute t strategy =
  Mutex.lock t.lock;
  if t.shutdown_complete then (
    Mutex.unlock t.lock;
    raise (Failure "Already shutdown")
  );
  
  match strategy with
  | Immediate ->
      List.iter (fun handler -> handler ()) t.handlers;
      t.shutdown_complete <- true;
      Mutex.unlock t.lock
      
  | Flush_pending ->
      Mutex.unlock t.lock;
      (* All handlers run concurrently *)
      let threads = List.map (fun h -> Thread.create h ()) t.handlers in
      List.iter Thread.join threads;
      Mutex.lock t.lock;
      t.shutdown_complete <- true;
      Mutex.unlock t.lock
      
  | Graceful timeout ->
      Mutex.unlock t.lock;
      (* Run with timeout protection *)
      let deadline = Unix.gettimeofday () +. timeout in
      let run_handler h =
        try
          let remaining = deadline -. Unix.gettimeofday () in
          if remaining > 0. then (
            h ();
            if Unix.gettimeofday () > deadline then raise (Failure "Timeout")
          )
        with exn ->
          Printf.eprintf "Shutdown handler failed: %s\n" (Printexc.to_string exn)
      in
      List.iter run_handler t.handlers;
      Mutex.lock t.lock;
      t.shutdown_complete <- true;
      Mutex.unlock t.lock
```

### 5. `lib/circuit_breaker.mli` (Public Interface)

```ocaml
(** Circuit breaker for error recovery *)

type state = Closed | Open | Half_open

type t

val create :
  failure_threshold:int ->
  reset_timeout_ms:int ->
  unit -> t

val call : t -> (unit -> unit) -> bool
(** Call protected function, return success *)

val get_state : t -> state
val reset : t -> unit
```

**State Machine**:
```
Closed state:
  - Calls pass through
  - Count failures
  - On failure_threshold: Open
  - Reset timer

Open state:
  - Calls fail immediately
  - Wait reset_timeout_ms
  - Transition to Half_open

Half_open state:
  - Allow one test call
  - If succeeds: Closed (reset)
  - If fails: Open (reset timer)
```

**Data Structure**:
```ocaml
type t = {
  mutable state: state;
  mutable failure_count: int;
  failure_threshold: int;
  reset_timeout_ms: int;
  mutable last_failure: float;
  lock: Mutex.t;
}
```

### 6. `lib/memory_tracking.mli` (Public Interface)

```ocaml
(** Memory usage monitoring and limits *)

type config = {
  max_queue_bytes: int;
  max_event_size_bytes: int;
  on_limit_exceeded: unit -> unit;
}

type t

val create : config -> t
val set_config : t -> config -> unit
val record_enqueue : t -> bytes:int -> unit
val record_dequeue : t -> bytes:int -> unit
val get_usage : t -> int
val is_over_limit : t -> bool
val trim_to_limit : t -> unit
```

---

## Integration Points

### Step 1: Update `lib/composite_sink.ml`

Add error handling per sink:

```ocaml
(** Emit to all sinks, collecting errors *)
let emit_safe t event =
  List.iter (fun sink ->
    try
      sink.emit_fn event
    with exn ->
      (* Record error in metrics, continue to next sink *)
      Printf.eprintf "Sink emit error: %s\n" (Printexc.to_string exn)
  ) t
```

### Step 2: Update `lib/configuration.ml`

Add fluent API methods:

```ocaml
(** Wrap recent sink with queue *)
let with_queue ?max_size ?batch_size config =
  match config.sinks with
  | [] -> config
  | sink_config :: rest ->
      let queued_sink = Async_sink_queue.create default_config sink_config.sink_fn in
      let new_sink_fn = { ... wrap queued ... } in
      {config with sinks = {sink_fn=new_sink_fn; min_level=sink_config.min_level} :: rest}

(** Enable metrics *)
let with_metrics ?collect config =
  if collect then {config with metrics = Some Metrics.create ()} else config

(** Set shutdown timeout *)
let with_shutdown_timeout seconds config =
  {config with shutdown_timeout = Some seconds}
```

### Step 3: Update `lib/logger.ml`

Add new fields:

```ocaml
type logger_impl = {
  min_level: Level.t;
  sinks: Composite_sink.sink_fn list;
  enrichers: (Log_event.t -> Log_event.t) list;
  filters: (Log_event.t -> bool) list;
  context_properties: (string * Yojson.Safe.t) list;
  source: string option;
  metrics: Metrics.t option;        (* NEW *)
  shutdown_ctrl: Shutdown.t option; (* NEW *)
}

(** Shutdown handler *)
let shutdown t strategy =
  match t.shutdown_ctrl with
  | None -> ()
  | Some ctrl -> Shutdown.execute ctrl strategy

(** Get metrics *)
let get_metrics t =
  match t.metrics with
  | None -> []
  | Some m -> Metrics.get_all_metrics m
```

### Step 4: Update `lib/log_context.ml`

Add timeout support:

```ocaml
(** Property with automatic cleanup *)
let with_property_timeout key value timeout_ms f =
  with_property key value (fun () ->
    let result = f () in
    (* Could use timer thread, but for now sync *)
    result
  )
```

---

## Testing Strategy

### Unit Tests for Each Module

**Async_sink_queue Tests** (5+ tests):
```ocaml
let test_enqueue_normal () =
  let sink = Mock_sink.create () in
  let queue = Async_sink_queue.create default_config sink in
  let event = Log_event.create ~level:Level.Information ... in
  Async_sink_queue.enqueue queue event;
  assert (Async_sink_queue.get_queue_depth queue = 1)

let test_enqueue_full_drops () =
  let queue = Async_sink_queue.create {max_queue_size=2} sink in
  enqueue queue event1;
  enqueue queue event2;
  enqueue queue event3;  (* Should drop oldest *)
  assert (get_queue_depth queue = 2);
  assert (sink received event2 and event3, not event1)

let test_flush_empties_queue () =
  enqueue queue event;
  Async_sink_queue.flush queue;
  assert (get_queue_depth queue = 0)

let test_concurrent_enqueue () =
  (* Thread 1 enqueues while thread 2 flushes *)
  let t1 = Thread.create (fun () -> for i = 1 to 1000 do enqueue queue event done) () in
  let t2 = Thread.create (fun () -> for i = 1 to 100 do flush queue; Thread.delay 0.001 done) () in
  Thread.join t1; Thread.join t2;
  assert (queue properly handled concurrent access)
```

**Metrics Tests** (5+ tests):
```ocaml
let test_record_event () =
  let m = Metrics.create () in
  Metrics.record_event m ~sink_id:"file" ~latency_us:1.5;
  let metrics = Metrics.get_sink_metrics m "file" in
  assert (metrics.events_total = 1)

let test_latency_percentiles () =
  let m = Metrics.create () in
  List.iter (fun lat -> Metrics.record_event m ~sink_id:"s" ~latency_us:lat)
    [1.0; 2.0; 3.0; 4.0; 5.0];
  let metrics = Metrics.get_sink_metrics m "s" in
  assert (metrics.latency_p50_us = 3.0)
  assert (metrics.latency_p95_us >= 4.0)
```

**Shutdown Tests** (4+ tests):
```ocaml
let test_immediate_shutdown () =
  let s = Shutdown.create () in
  let called = ref false in
  Shutdown.register s (fun () -> called := true);
  Shutdown.execute s Shutdown.Immediate;
  assert !called

let test_graceful_timeout () =
  let s = Shutdown.create () in
  let start = Unix.gettimeofday () in
  Shutdown.register s (fun () -> Thread.delay 10.0);  (* Would hang *)
  Shutdown.execute s (Shutdown.Graceful 0.1);  (* 100ms timeout *)
  let elapsed = Unix.gettimeofday () -. start in
  assert (elapsed < 1.0)  (* Should timeout quickly *)
```

**Circuit Breaker Tests** (4+ tests):
```ocaml
let test_closed_state () =
  let cb = Circuit_breaker.create ~failure_threshold:3 ~reset_timeout_ms:100 () in
  assert (call cb (fun () -> ()) = true);
  assert (get_state cb = Closed)

let test_open_on_failures () =
  let cb = Circuit_breaker.create ~failure_threshold:2 () in
  assert (call cb (fun () -> raise (Failure "")) = false);
  assert (call cb (fun () -> raise (Failure "")) = false);
  assert (get_state cb = Open);
  assert (call cb (fun () -> ()) = false)  (* Fails fast *)
```

---

## Validation Checklist

Before marking Phase 6 complete:

- [ ] **Build**
  - [ ] `dune build` completes without errors
  - [ ] No compiler warnings
  - [ ] No deprecation notices

- [ ] **Tests**
  - [ ] All 63+ existing tests pass
  - [ ] 20+ new Phase 6 tests pass
  - [ ] Concurrent tests run without race conditions
  - [ ] No test timeouts

- [ ] **Benchmarks**
  - [ ] `dune exec benchmarks/benchmark.exe` runs
  - [ ] Sync emit baseline measured
  - [ ] Queued emit shows improvement
  - [ ] Metrics overhead < 5%

- [ ] **API Completeness**
  - [ ] Configuration supports all Phase 6 features
  - [ ] Logger has shutdown, metrics, monitoring
  - [ ] Examples show production patterns
  - [ ] Documentation updated

- [ ] **Production Readiness**
  - [ ] Graceful shutdown tested
  - [ ] Error recovery tested
  - [ ] Memory limits enforced
  - [ ] High-volume scenarios tested

---

## Success Criteria

**Functional**:
- ✅ Async queueing functional with configurable size
- ✅ Metrics collected and queryable
- ✅ Graceful shutdown with timeout
- ✅ Circuit breaker recovers from transient failures
- ✅ Memory limits prevent unbounded growth

**Performance**:
- ✅ Queued emit < 1μs (vs 4.2μs sync console)
- ✅ Flush batches reduce syscalls
- ✅ Metrics overhead < 5%
- ✅ Shutdown completes in < 100ms

**Quality**:
- ✅ Zero regressions in existing tests
- ✅ 20+ new tests, all passing
- ✅ Clean build, no warnings
- ✅ Thread-safe under concurrent load

---

## Debugging Tips

**Memory Leak Detection**:
```bash
valgrind --leak-check=full dune exec test/test_phase6.exe
```

**Race Condition Detection**:
```bash
dune exec test/test_phase6_concurrent.exe
```

**Performance Profiling**:
```bash
perf record -g dune exec benchmarks/benchmark.exe -- -cycles -q 10
perf report
```

**Mutex Contention**:
```ocaml
(* Add to metrics *)
mutable lock_wait_count: int;  (* Count lock acquisitions *)
mutable lock_wait_time_us: float;  (* Total lock wait *)
```

---

## Reference Documents

- `PHASE6_ANALYSIS.md` - Detailed requirements
- `PHASE6_CURRENT_LIMITATIONS.md` - What to fix
- `AGENTS.md` - Project guidelines
- `DEPLOYMENT.md` - Production patterns
- `CONFIGURATION.md` - Configuration API

---

**Status**: Ready for implementation  
**Next Step**: Begin Sprint 1 (Async Queueing)  
**Estimated Timeline**: 5 hours total, ~1 hour per sprint
