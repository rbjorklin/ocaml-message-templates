# Plan 5: Fix Async Queue Busy-Waiting

## Status
**Priority:** MEDIUM  
**Estimated Effort:** 2-3 hours  
**Risk Level:** Low

## Problem Statement

The `async_sink_queue.ml` implementation uses busy-waiting for the background flush thread:

```ocaml
let rec sleep_loop () =
  let elapsed = Unix.gettimeofday () -. start in
  if elapsed < total_sleep then (
    Thread.delay sleep_chunk;  (* Sleeps 10ms *)
    let shutdown_now = with_lock t (fun () -> t.shutdown) in
    if not shutdown_now then sleep_loop () )
```

### Issues

1. **CPU Wastage**: Wakes up every 10ms to check if it should shutdown, even when idle
2. **Latency**: Actual flush interval is approximate (could be up to 10ms late)
3. **Battery/Resource Drain**: Unnecessary wakeups on laptops/mobile
4. **Scalability**: Worsens with shorter flush intervals

### Current Flow

```
Background Thread:
  Loop:
    sleep 10ms chunks
    check shutdown flag
    sleep more if needed
    flush events
```

## Solution

Use condition variables (`Condition.t`) for proper signaling:
- Thread sleeps until signaled or timeout
- `enqueue` signals when new events arrive
- `close` signals for immediate shutdown
- More precise timing, no busy-waiting

## Implementation Steps

### Step 1: Add Condition Variable to State

**File:** `lib/async_sink_queue.ml`

```ocaml
type t =
  { mutable events: Log_event.t option array
  ; mutable head: int
  ; mutable tail: int
  ; mutable size: int
  ; config: config
  ; lock: Mutex.t
  ; not_empty: Condition.t  (* NEW: signaled when events are added *)
  ; not_full: Condition.t   (* NEW: signaled when space available *)
  ; mutable background_thread: Thread.t option
  ; mutable shutdown: bool
  ; mutable stats: stats
  ; sink_fn: Log_event.t -> unit }
```

### Step 2: Update Create Function

```ocaml
let create config sink_fn =
  let t =
    { events= Array.make config.max_queue_size None
    ; head= 0
    ; tail= 0
    ; size= 0
    ; config
    ; lock= Mutex.create ()
    ; not_empty= Condition.create ()  (* NEW *)
    ; not_full= Condition.create ()   (* NEW *)
    ; background_thread= None
    ; shutdown= false
    ; stats=
        {total_enqueued= 0; total_emitted= 0; total_dropped= 0; total_errors= 0}
    ; sink_fn }
  in
  let thread =
    Thread.create
      (fun () ->
        let rec loop () =
          with_lock t (fun () ->
              (* Wait for events or timeout or shutdown *)
              let deadline = Unix.gettimeofday () +. 
                (float_of_int config.flush_interval_ms /. 1000.0) in
              
              while t.size = 0 && not t.shutdown && 
                    Unix.gettimeofday () < deadline do
                let remaining = deadline -. Unix.gettimeofday () in
                if remaining > 0.0 then
                  Condition.wait_timeout t.not_empty t.lock remaining
              done);
          
          (* Flush any pending events *)
          if t.size > 0 then (
            try do_flush t
            with exn ->
              config.error_handler exn;
              with_lock t (fun () ->
                t.stats.total_errors <- t.stats.total_errors + 1));
          
          (* Check shutdown *)
          let should_stop = with_lock t (fun () -> t.shutdown) in
          if not should_stop then loop ()
        in
        loop ())
      ()
  in
  t.background_thread <- Some thread;
  t
```

### Step 3: Update Enqueue to Signal

```ocaml
let enqueue t event =
  let should_signal = ref false in
  with_lock t (fun () ->
      t.stats.total_enqueued <- t.stats.total_enqueued + 1;

      if t.size >= t.config.max_queue_size then (
        (* Drop oldest event *)
        if t.size > 0 then (
          t.events.(t.head) <- None;
          t.head <- (t.head + 1) mod t.config.max_queue_size;
          t.size <- t.size - 1;
          t.stats.total_dropped <- t.stats.total_dropped + 1 );
        if t.size >= t.config.max_queue_size then
          t.stats.total_dropped <- t.stats.total_dropped + 1
        else (
          t.events.(t.tail) <- Some event;
          t.tail <- (t.tail + 1) mod t.config.max_queue_size;
          t.size <- t.size + 1;
          should_signal := true;
          if t.size > t.config.back_pressure_threshold then
            Printf.eprintf "Warning: queue depth %d/%d\n" t.size
              t.config.max_queue_size ) )
      else (
        t.events.(t.tail) <- Some event;
        t.tail <- (t.tail + 1) mod t.config.max_queue_size;
        t.size <- t.size + 1;
        should_signal := true;
        if t.size > t.config.back_pressure_threshold then
          Printf.eprintf "Warning: queue depth %d/%d\n" t.size
            t.config.max_queue_size ) );
  
  (* Signal outside the lock to avoid waking thread while holding lock *)
  if !should_signal then Condition.signal t.not_empty
```

### Step 4: Update Close to Signal

```ocaml
let close t =
  with_lock t (fun () -> t.shutdown <- true);
  Condition.signal t.not_empty;  (* Wake up thread immediately *)
  
  (match t.background_thread with
  | Some thread ->
      (try Thread.join thread with _ -> ());
      t.background_thread <- None
  | None -> ());
  
  do_flush t
```

### Step 5: Add Wait With Timeout Helper

**File:** `lib/async_sink_queue.ml`

OCaml's standard library doesn't have `Condition.wait_timeout`, so implement it:

```ocaml
(* Wait on condition with timeout *)
let condition_wait_timeout cond mutex timeout_secs =
  let start = Unix.gettimeofday () in
  let deadline = start +. timeout_secs in
  
  let rec wait_remaining () =
    let now = Unix.gettimeofday () in
    if now >= deadline then false
    else (
      (* Use Unix.select for sub-second precision *)
      let _, _, _ = Unix.select [] [] [] (deadline -. now) in
      (* Check if condition was signaled *)
      true)
  in
  
  Mutex.unlock mutex;
  let signaled = wait_remaining () in
  Mutex.lock mutex;
  signaled
```

**Alternative**: Use the `thread` library's event-based waiting:

```ocaml
(* Use Thread.wait_signal with a signal handler *)
(* More complex but precise *)
```

### Step 6: Simpler Alternative - Event-Based

If condition variables are problematic, use an event channel:

```ocaml
type t =
  { (* ... other fields ... *)
    ; event_added: unit Event.channel
    ; shutdown_requested: unit Event.channel }

let create config sink_fn =
  let t =
    { (* ... *)
    ; event_added= Event.new_channel ()
    ; shutdown_requested= Event.new_channel () }
  in
  let thread =
    Thread.create
      (fun () ->
        let rec loop () =
          let flush_interval = float_of_int config.flush_interval_ms /. 1000.0 in
          let selector =
            [ Event.receive t.event_added
            ; Event.receive t.shutdown_requested
            ; Event.timeout flush_interval ]
          in
          match Event.select selector with
          | `Event () ->  (* Event added or shutdown *)
              do_flush t;
              loop ()
          | `Timeout ->  (* Flush interval elapsed *)
              do_flush t;
              loop ()
        in
        loop ())
      ()
  in
  t.background_thread <- Some thread;
  t

let enqueue t event =
  (* ... add event ... *)
  Event.sync (Event.send t.event_added ())
```

## Alternative: Lwt-Style Sleeping

For even better resource usage, use Lwt-style sleeping:

```ocaml
type t =
  { (* ... *)
  ; mutable flush_timer: float option }

let create config sink_fn =
  (* ... *)
  let thread =
    Thread.create
      (fun () ->
        let rec loop () =
          let next_wake = 
            with_lock t (fun () ->
              if t.size > 0 then
                Some (Unix.gettimeofday () +. 
                  (float_of_int config.flush_interval_ms /. 1000.0))
              else
                None)
          in
          
          match next_wake with
          | None ->
              (* Wait indefinitely for event *)
              with_lock t (fun () ->
                while t.size = 0 && not t.shutdown do
                  Condition.wait t.not_empty t.lock
                done)
          | Some deadline ->
              let now = Unix.gettimeofday () in
              if now < deadline then
                with_lock t (fun () ->
                  while t.size = 0 && not t.shutdown && 
                        Unix.gettimeofday () < deadline do
                    let remaining = deadline -. Unix.gettimeofday () in
                    ignore (Condition.wait_timeout t.not_empty t.lock remaining)
                  done);
          
          do_flush t;
          
          let should_stop = with_lock t (fun () -> t.shutdown) in
          if not should_stop then loop ()
        in
        loop ())
      ()
  in
  (* ... *)
```

## Testing Strategy

### 1. Performance Tests

```ocaml
let test_no_busy_waiting () =
  let queue = Async_sink_queue.create default_config (fun _ -> ()) in
  
  (* Let it idle for 1 second *)
  Thread.delay 1.0;
  
  (* Check CPU usage - should be minimal *)
  (* This is platform-specific, might need external monitoring *)
  
  Async_sink_queue.close queue
```

### 2. Latency Tests

```ocaml
let test_flush_timing () =
  let emitted = ref [] in
  let config = {default_config with flush_interval_ms= 100} in
  let queue = Async_sink_queue.create config (fun ev -> 
    emitted := (Unix.gettimeofday (), ev) :: !emitted) in
  
  let enqueue_time = Unix.gettimeofday () in
  Async_sink_queue.enqueue queue (create_test_event ());
  
  (* Wait for flush *)
  Thread.delay 0.15;
  
  Async_sink_queue.close queue;
  
  (* Check that flush happened within ~100ms, not 200ms+ *)
  match !emitted with
  | (flush_time, _) :: _ ->
      let latency = flush_time -. enqueue_time in
      Alcotest.(check bool "flush within 150ms" true (latency < 0.15))
  | [] -> Alcotest.fail "event not flushed"
```

### 3. Shutdown Responsiveness Tests

```ocaml
let test_quick_shutdown () =
  let config = {default_config with flush_interval_ms= 5000} in
  (* 5 second flush interval *)
  let queue = Async_sink_queue.create config (fun _ -> ()) in
  
  let start = Unix.gettimeofday () in
  Async_sink_queue.close queue;
  let elapsed = Unix.gettimeofday () -. start in
  
  (* Should close immediately, not wait 5 seconds *)
  Alcotest.(check bool "closes quickly" true (elapsed < 0.1))
```

### 4. Stress Tests

```ocaml
let test_high_throughput () =
  let counter = ref 0 in
  let config = {default_config with batch_size= 100} in
  let queue = Async_sink_queue.create config (fun _ -> 
    incr counter) in
  
  (* Enqueue 10000 events from multiple threads *)
  let threads = List.init 4 (fun _ ->
    Thread.create (fun () ->
      for _ = 1 to 2500 do
        Async_sink_queue.enqueue queue (create_test_event ())
      done) ())
  in
  
  List.iter Thread.join threads;
  Async_sink_queue.close queue;
  
  Alcotest.(check int "all events processed" 10000 !counter)
```

## Migration Guide

### For Library Users

No API changes - purely internal improvement. Users benefit from:
- Lower CPU usage when idle
- Faster shutdown
- More predictable flush timing

### Behavioral Changes

1. **More responsive shutdown**: `close()` returns immediately instead of waiting for sleep loop
2. **Precise flush timing**: Events flushed closer to the configured interval
3. **Backpressure signals**: New `not_full` condition could enable blocking enqueue mode

## Success Criteria

- [ ] Condition variables implemented
- [ ] No busy-waiting in background thread
- [ ] Shutdown is immediate (< 100ms)
- [ ] Flush timing within 10% of configured interval
- [ ] All existing tests pass
- [ ] CPU usage < 1% when idle (was ~5-10% with busy-waiting)
- [ ] Throughput maintained or improved

## Related Files

- `lib/async_sink_queue.ml`
- `lib/async_sink_queue.mli`
- `test/test_phase6_async_queue.ml`

## Notes

- Condition.wait_timeout may need platform-specific implementation
- Consider adding `blocking_enqueue` option (waits for space instead of dropping)
- Monitor for deadlocks - ensure condition is signaled on all code paths
