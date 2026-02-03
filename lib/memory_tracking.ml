(** Memory usage monitoring and limits implementation *)

type config =
  { max_queue_bytes: int
  ; max_event_size_bytes: int
  ; on_limit_exceeded: unit -> unit }

type t =
  { mutable config: config
  ; mutable current_usage: int
  ; lock: Mutex.t }

let default_config =
  { max_queue_bytes= 100 * 1024 * 1024
  ; (* 100 MB *)
    max_event_size_bytes= 1024 * 1024
  ; (* 1 MB *)
    on_limit_exceeded= (fun () -> ()) }
;;

let create config =
  if config.max_queue_bytes <= 0 then
    raise (Invalid_argument "max_queue_bytes must be positive");
  if config.max_event_size_bytes <= 0 then
    raise (Invalid_argument "max_event_size_bytes must be positive");
  {config; current_usage= 0; lock= Mutex.create ()}
;;

let set_config t config =
  Mutex.lock t.lock;
  t.config <- config;
  (* Check if new limit causes overflow *)
  if t.current_usage > config.max_queue_bytes then
    t.config.on_limit_exceeded ();
  Mutex.unlock t.lock
;;

let record_enqueue t ~bytes =
  Mutex.lock t.lock;
  (* Check event size limit *)
  if bytes > t.config.max_event_size_bytes then (
    Mutex.unlock t.lock;
    raise
      (Invalid_argument
         (Printf.sprintf "Event size %d exceeds max_event_size_bytes %d" bytes
            t.config.max_event_size_bytes ) ) );
  t.current_usage <- t.current_usage + bytes;
  (* Check if we exceeded the limit *)
  if t.current_usage > t.config.max_queue_bytes then
    t.config.on_limit_exceeded ();
  Mutex.unlock t.lock
;;

let record_dequeue t ~bytes =
  Mutex.lock t.lock;
  t.current_usage <- max 0 (t.current_usage - bytes);
  Mutex.unlock t.lock
;;

let get_usage t =
  Mutex.lock t.lock;
  let result = t.current_usage in
  Mutex.unlock t.lock; result
;;

let is_over_limit t =
  Mutex.lock t.lock;
  let result = t.current_usage > t.config.max_queue_bytes in
  Mutex.unlock t.lock; result
;;

let trim_to_limit t =
  Mutex.lock t.lock;
  if t.current_usage > t.config.max_queue_bytes then
    t.config.on_limit_exceeded ();
  Mutex.unlock t.lock
;;

let get_config t =
  Mutex.lock t.lock;
  let result = t.config in
  Mutex.unlock t.lock; result
;;
