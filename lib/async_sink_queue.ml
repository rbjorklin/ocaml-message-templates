(** Non-blocking event queue for async sink batching with circuit breaker
    support *)

type config =
  { max_queue_size: int
  ; flush_interval_ms: int
  ; batch_size: int
  ; back_pressure_threshold: int
  ; error_handler: exn -> unit
  ; circuit_breaker: Circuit_breaker.t option }

let default_config =
  { max_queue_size= 1000
  ; flush_interval_ms= 100
  ; batch_size= 50
  ; back_pressure_threshold= 800
  ; error_handler=
      (fun exn -> Printf.eprintf "Queue error: %s\n" (Printexc.to_string exn))
  ; circuit_breaker= None }
;;

(** Statistics record *)
type stats =
  { mutable total_enqueued: int
  ; mutable total_emitted: int
  ; mutable total_dropped: int
  ; mutable total_errors: int }

(** Internal queue state *)
type t =
  { mutable events: Log_event.t option array
  ; mutable head: int (* Read position *)
  ; mutable tail: int (* Write position *)
  ; mutable size: int (* Number of events in queue *)
  ; config: config
  ; lock: Mutex.t
  ; mutable background_thread: Thread.t option
  ; mutable shutdown: bool
  ; mutable stats: stats
  ; sink_fn: Log_event.t -> unit (* Underlying sink *) }

(** Helper to safely execute code with mutex held *)
let with_lock t f =
  Mutex.lock t.lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.lock) f
;;

(** Emit an event with circuit breaker protection *)
let emit_with_circuit_breaker t event =
  match t.config.circuit_breaker with
  | None ->
      (* No circuit breaker: emit directly *)
      t.sink_fn event;
      t.stats.total_emitted <- t.stats.total_emitted + 1
  | Some cb -> (
    (* Use circuit breaker to protect the sink *)
    match Circuit_breaker.call cb (fun () -> t.sink_fn event) with
    | Some () -> t.stats.total_emitted <- t.stats.total_emitted + 1
    | None ->
        (* Circuit breaker is open: count as dropped *)
        t.stats.total_dropped <- t.stats.total_dropped + 1 )
;;

(** Flush all queued events *)
let do_flush t =
  let flush_batch () =
    let events_to_emit =
      with_lock t (fun () ->
          if t.size = 0 then
            []
          else
            (* Take up to batch_size events *)
            let batch_count = min t.config.batch_size t.size in
            let events = ref [] in
            for _i = 1 to batch_count do
              match t.events.(t.head) with
              | Some event ->
                  events := event :: !events;
                  t.events.(t.head) <- None;
                  t.head <- (t.head + 1) mod t.config.max_queue_size;
                  t.size <- t.size - 1
              | None -> () (* Should not happen *)
            done;
            List.rev !events )
    in
    match events_to_emit with
    | [] -> false (* No more to flush *)
    | events ->
        (* Emit outside the lock *)
        List.iter
          (fun event ->
            try emit_with_circuit_breaker t event
            with exn ->
              t.config.error_handler exn;
              t.stats.total_errors <- t.stats.total_errors + 1 )
          events;
        true (* More to flush *)
  in
  (* Keep flushing until empty *)
  while flush_batch () do
    ()
  done
;;

(** Get current queue depth *)
let get_queue_depth t = with_lock t (fun () -> t.size)

(** Get statistics *)
let get_stats t =
  with_lock t (fun () ->
      { total_enqueued= t.stats.total_enqueued
      ; total_emitted= t.stats.total_emitted
      ; total_dropped= t.stats.total_dropped
      ; total_errors= t.stats.total_errors } )
;;

(** Non-blocking enqueue *)
let enqueue t event =
  with_lock t (fun () ->
      t.stats.total_enqueued <- t.stats.total_enqueued + 1;

      if t.size >= t.config.max_queue_size then (
        (* Queue full: drop oldest (move head forward) *)
        if t.size > 0 then (
          t.events.(t.head) <- None;
          t.head <- (t.head + 1) mod t.config.max_queue_size;
          t.size <- t.size - 1;
          t.stats.total_dropped <- t.stats.total_dropped + 1 );
        (* Still drop this event if we hit the limit after dropping *)
        if t.size >= t.config.max_queue_size then
          t.stats.total_dropped <- t.stats.total_dropped + 1
        else (
          (* Add event after making space *)
          t.events.(t.tail) <- Some event;
          t.tail <- (t.tail + 1) mod t.config.max_queue_size;
          t.size <- t.size + 1;

          (* Warn if approaching limit *)
          if t.size > t.config.back_pressure_threshold then
            Printf.eprintf "Warning: queue depth %d/%d\n" t.size
              t.config.max_queue_size ) )
      else (
        (* Queue has space: add event *)
        t.events.(t.tail) <- Some event;
        t.tail <- (t.tail + 1) mod t.config.max_queue_size;
        t.size <- t.size + 1;

        (* Warn if approaching limit *)
        if t.size > t.config.back_pressure_threshold then
          Printf.eprintf "Warning: queue depth %d/%d\n" t.size
            t.config.max_queue_size ) )
;;

(** Public flush function *)
let flush t = do_flush t

(** Check if alive *)
let is_alive t = with_lock t (fun () -> not t.shutdown)

(** Graceful close *)
let close t =
  with_lock t (fun () -> t.shutdown <- true);

  (* Wait for background thread *)
  ( match t.background_thread with
  | Some thread ->
      (try Thread.join thread with _ -> ());
      t.background_thread <- None
  | None -> () );

  (* Final flush *)
  do_flush t
;;

(** Create a new queue *)
let create config sink_fn =
  let t =
    { events= Array.make config.max_queue_size None
    ; head= 0
    ; tail= 0
    ; size= 0
    ; config
    ; lock= Mutex.create ()
    ; background_thread= None
    ; shutdown= false
    ; stats=
        {total_enqueued= 0; total_emitted= 0; total_dropped= 0; total_errors= 0}
    ; sink_fn }
  in
  (* Start background flush thread *)
  let thread =
    Thread.create
      (fun () ->
        let rec loop () =
          let should_shutdown = with_lock t (fun () -> t.shutdown) in
          if not should_shutdown then (
            (* Sleep in small increments to allow responsive shutdown *)
            let sleep_chunk = 0.01 in
            (* 10ms chunks *)
            let total_sleep = float_of_int config.flush_interval_ms /. 1000.0 in
            let start = Unix.gettimeofday () in
            let rec sleep_loop () =
              let elapsed = Unix.gettimeofday () -. start in
              if elapsed < total_sleep then (
                Thread.delay sleep_chunk;
                let shutdown_now = with_lock t (fun () -> t.shutdown) in
                if not shutdown_now then
                  sleep_loop () )
            in
            sleep_loop ();
            (* Flush after waking up *)
            try do_flush t
            with exn ->
              config.error_handler exn;
              with_lock t (fun () ->
                  t.stats.total_errors <- t.stats.total_errors + 1 );
              loop () )
        in
        loop () )
      ()
  in
  t.background_thread <- Some thread;
  t
;;

(** Create a queue with circuit breaker protection *)
let create_with_circuit_breaker config sink_fn =
  let cb =
    Circuit_breaker.create ~failure_threshold:5 ~reset_timeout_ms:5000 ()
  in
  create {config with circuit_breaker= Some cb} sink_fn
;;
