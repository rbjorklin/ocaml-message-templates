(** Circuit breaker pattern implementation *)

type state =
  | Closed
  | Open
  | Half_open

type t =
  { mutable state: state
  ; mutable failure_count: int
  ; failure_threshold: int
  ; reset_timeout_ms: int
  ; mutable last_failure_time: float
  ; lock: Mutex.t }

let get_time_ms () = Unix.gettimeofday () *. 1000.0

let create ~failure_threshold ~reset_timeout_ms () =
  if failure_threshold <= 0 then
    raise (Invalid_argument "failure_threshold must be positive");
  if reset_timeout_ms <= 0 then
    raise (Invalid_argument "reset_timeout_ms must be positive");
  { state= Closed
  ; failure_count= 0
  ; failure_threshold
  ; reset_timeout_ms
  ; last_failure_time= 0.0
  ; lock= Mutex.create () }
;;

let get_state t =
  Mutex.lock t.lock;
  let current_state = t.state in

  (* Check if we should transition from Open to Half_open *)
  ( if current_state = Open then
      let elapsed = get_time_ms () -. t.last_failure_time in
      if elapsed >= float_of_int t.reset_timeout_ms then
        t.state <- Half_open );

  let result = t.state in
  Mutex.unlock t.lock; result
;;

let record_success t =
  t.failure_count <- 0;
  if t.state = Half_open then
    t.state <- Closed
;;

let record_failure t =
  t.failure_count <- t.failure_count + 1;
  t.last_failure_time <- get_time_ms ();
  if t.failure_count >= t.failure_threshold then
    t.state <- Open
;;

let call t f =
  Mutex.lock t.lock;

  (* Check if we should transition from Open to Half_open *)
  ( if t.state = Open then
      let elapsed = get_time_ms () -. t.last_failure_time in
      if elapsed >= float_of_int t.reset_timeout_ms then
        t.state <- Half_open );

  let can_attempt = t.state <> Open in

  if not can_attempt then (
    Mutex.unlock t.lock; None )
  else (
    (* Execute the call outside the lock *)
    Mutex.unlock t.lock;
    try
      let result = f () in
      Mutex.lock t.lock; record_success t; Mutex.unlock t.lock; Some result
    with _exn ->
      Mutex.lock t.lock; record_failure t; Mutex.unlock t.lock; None )
;;

let reset t =
  Mutex.lock t.lock;
  t.state <- Closed;
  t.failure_count <- 0;
  Mutex.unlock t.lock
;;

(** Simple stats as a tuple: (failure_count, success_count, last_failure_time)
*)
let get_stats t =
  Mutex.lock t.lock;
  let result = (t.failure_count, t.state, t.last_failure_time) in
  Mutex.unlock t.lock; result
;;
