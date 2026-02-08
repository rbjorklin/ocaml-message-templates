(** Structured shutdown protocol implementation *)

type shutdown_strategy =
  | Immediate
  | Flush_pending
  | Graceful of float

type t =
  { mutable handlers: (unit -> unit) list
  ; lock: Mutex.t
  ; mutable shutdown_complete: bool }

let create () = {handlers= []; lock= Mutex.create (); shutdown_complete= false}

(** Execute f with lock held, ensuring unlock is always called *)
let with_lock t f =
  Mutex.lock t.lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.lock) f
;;

let register t handler =
  with_lock t (fun () -> t.handlers <- handler :: t.handlers)
;;

let execute_immediate t =
  (* Execute in LIFO order - reverse the list *)
  List.iter
    (fun handler ->
      try handler ()
      with exn ->
        Printf.eprintf "Shutdown handler error: %s\n" (Printexc.to_string exn) )
    (List.rev t.handlers)
;;

let execute_flush_pending t =
  (* Execute handlers concurrently using threads, in LIFO order *)
  let threads =
    List.map
      (fun handler ->
        Thread.create
          (fun () ->
            try handler ()
            with exn ->
              Printf.eprintf "Shutdown handler error: %s\n"
                (Printexc.to_string exn) )
          () )
      (List.rev t.handlers)
  in
  (* Wait for all threads to complete *)
  List.iter Thread.join threads
;;

let execute_graceful t timeout_sec =
  let deadline = Unix.gettimeofday () +. timeout_sec in
  let run_handler handler =
    try
      let remaining = deadline -. Unix.gettimeofday () in
      if remaining > 0.0 then (
        handler ();
        if Unix.gettimeofday () > deadline then
          Printf.eprintf "Shutdown handler exceeded deadline\n" )
      else
        Printf.eprintf "Shutdown handler skipped: deadline exceeded\n"
    with exn ->
      Printf.eprintf "Shutdown handler error: %s\n" (Printexc.to_string exn)
  in
  (* Execute in LIFO order - reverse the list *)
  List.iter run_handler (List.rev t.handlers)
;;

let execute t strategy =
  let handlers_copy =
    with_lock t (fun () ->
        if t.shutdown_complete then
          raise (Failure "Shutdown already executed");
        let handlers_copy = t.handlers in
        t.shutdown_complete <- true;
        handlers_copy )
  in

  match strategy with
  | Immediate -> execute_immediate {t with handlers= handlers_copy}
  | Flush_pending -> execute_flush_pending {t with handlers= handlers_copy}
  | Graceful timeout_sec ->
      execute_graceful {t with handlers= handlers_copy} timeout_sec
;;

let is_shutdown t = with_lock t (fun () -> t.shutdown_complete)

let reset t =
  with_lock t (fun () ->
      t.handlers <- [];
      t.shutdown_complete <- false )
;;
