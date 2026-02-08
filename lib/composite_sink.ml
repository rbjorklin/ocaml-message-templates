(** Composite sink - routes log events to multiple sinks *)

type sink_fn =
  { emit_fn: Log_event.t -> unit
  ; flush_fn: unit -> unit
  ; close_fn: unit -> unit
  ; min_level: Level.t option }

type t = sink_fn list

(** Emit to all sinks that accept the event's level *)
let emit t event =
  let event_level = Log_event.get_level event in
  List.iter
    (fun sink ->
      match sink.min_level with
      | Some min_level when Level.compare event_level min_level < 0 ->
          () (* Skip - event level too low for this sink *)
      | _ -> sink.emit_fn event )
    t
;;

(** Flush all sinks *)
let flush t = List.iter (fun sink -> sink.flush_fn ()) t

(** Close all sinks *)
let close t = List.iter (fun sink -> sink.close_fn ()) t

(** Create a composite sink from sink functions *)
let create sinks = sinks
