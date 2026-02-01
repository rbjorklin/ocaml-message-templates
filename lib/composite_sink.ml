(** Composite sink - routes log events to multiple sinks *)

type sink_fn = {
  emit_fn : Log_event.t -> unit;
  flush_fn : unit -> unit;
  close_fn : unit -> unit;
}

type t = sink_fn list

(** Emit to all sinks *)
let emit t event =
  List.iter (fun sink ->
    sink.emit_fn event
  ) t

(** Flush all sinks *)
let flush t =
  List.iter (fun sink ->
    sink.flush_fn ()
  ) t

(** Close all sinks *)
let close t =
  List.iter (fun sink ->
    sink.close_fn ()
  ) t

(** Create a composite sink from sink functions *)
let create sinks =
  sinks
