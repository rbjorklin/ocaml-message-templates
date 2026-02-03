(** Non-blocking event queue for async sink batching *)

type config = {
  max_queue_size: int;
  flush_interval_ms: int;
  batch_size: int;
  back_pressure_threshold: int;
  error_handler: exn -> unit;
}

let default_config =
  { max_queue_size= 1000
  ; flush_interval_ms= 100
  ; batch_size= 50
  ; back_pressure_threshold= 800
  ; error_handler= (fun exn -> Printf.eprintf "Queue error: %s\n" (Printexc.to_string exn))
  }
;;

(** Statistics record *)
type stats = {
  mutable total_enqueued: int;
  mutable total_emitted: int;
  mutable total_dropped: int;
  mutable total_errors: int;
}

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
  ; sink_fn: Log_event.t -> unit (* Underlying sink *)
  }

(** Flush all queued events *)
let do_flush t =
  let flush_batch () =
    Mutex.lock t.lock;
    
    if t.size = 0 then (
      Mutex.unlock t.lock;
      false
    )
    else (
      (* Take up to batch_size events *)
      let batch_count = min t.config.batch_size t.size in
      let events_to_emit = ref [] in
      
      for _i = 1 to batch_count do
        match t.events.(t.head) with
        | Some event ->
            events_to_emit := event :: !events_to_emit;
            t.events.(t.head) <- None;
            t.head <- (t.head + 1) mod t.config.max_queue_size;
            t.size <- t.size - 1
        | None ->
            () (* Should not happen *)
      done;
      
      Mutex.unlock t.lock;
      
      (* Emit outside the lock *)
      List.iter
        (fun event ->
          try
            t.sink_fn event;
            t.stats.total_emitted <- t.stats.total_emitted + 1
          with exn ->
            t.config.error_handler exn;
            t.stats.total_errors <- t.stats.total_errors + 1 )
        (List.rev !events_to_emit);
      
      true (* More to flush *)
    )
  in
  (* Keep flushing until empty *)
  while flush_batch () do
    ()
  done


(** Get current queue depth *)
let get_queue_depth t =
  Mutex.lock t.lock;
  let depth = t.size in
  Mutex.unlock t.lock;
  depth

(** Get statistics *)
let get_stats t =
  Mutex.lock t.lock;
  let result =
    { total_enqueued= t.stats.total_enqueued
    ; total_emitted= t.stats.total_emitted
    ; total_dropped= t.stats.total_dropped
    ; total_errors= t.stats.total_errors
    }
  in
  Mutex.unlock t.lock;
  result

(** Non-blocking enqueue *)
let enqueue t event =
  Mutex.lock t.lock;
  try
    t.stats.total_enqueued <- t.stats.total_enqueued + 1;
    
    if t.size >= t.config.max_queue_size then (
      (* Queue full: drop oldest (move head forward) *)
      if t.size > 0 then (
        t.events.(t.head) <- None;
        t.head <- (t.head + 1) mod t.config.max_queue_size;
        t.size <- t.size - 1;
        t.stats.total_dropped <- t.stats.total_dropped + 1
      );
      (* Still drop this event if we hit the limit after dropping *)
      if t.size >= t.config.max_queue_size then (
        t.stats.total_dropped <- t.stats.total_dropped + 1;
        Mutex.unlock t.lock;
        ()
      )
      else (
        (* Add event after making space *)
        t.events.(t.tail) <- Some event;
        t.tail <- (t.tail + 1) mod t.config.max_queue_size;
        t.size <- t.size + 1;
        
        (* Warn if approaching limit *)
        if t.size > t.config.back_pressure_threshold then
          Printf.eprintf "Warning: queue depth %d/%d\n" t.size t.config.max_queue_size;
        
        Mutex.unlock t.lock
      )
    )
    else (
      (* Queue has space: add event *)
      t.events.(t.tail) <- Some event;
      t.tail <- (t.tail + 1) mod t.config.max_queue_size;
      t.size <- t.size + 1;
      
      (* Warn if approaching limit *)
      if t.size > t.config.back_pressure_threshold then
        Printf.eprintf "Warning: queue depth %d/%d\n" t.size t.config.max_queue_size;
      
      Mutex.unlock t.lock
    )
  with exn ->
    Mutex.unlock t.lock;
    raise exn

(** Public flush function *)
let flush t = do_flush t

(** Check if alive *)
let is_alive t =
  Mutex.lock t.lock;
  let result = not t.shutdown in
  Mutex.unlock t.lock;
  result

(** Graceful close *)
let close t =
  Mutex.lock t.lock;
  t.shutdown <- true;
  Mutex.unlock t.lock;
  
  (* Wait for background thread *)
  (match t.background_thread with
  | Some thread ->
      (try Thread.join thread with _ -> ());
      t.background_thread <- None
  | None -> ());
  
  (* Final flush *)
  do_flush t

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
    ; stats= {total_enqueued= 0; total_emitted= 0; total_dropped= 0; total_errors= 0}
    ; sink_fn
    }
  in
  (* Start background flush thread *)
  let thread =
    Thread.create (fun () ->
        while not t.shutdown do
          Thread.delay (float_of_int config.flush_interval_ms /. 1000.0);
          try do_flush t
          with exn ->
            config.error_handler exn;
            t.stats.total_errors <- t.stats.total_errors + 1
        done )
      ()
  in
  t.background_thread <- Some thread;
  t
