(** Eio sink interface - sync sink signatures for Eio fiber-based concurrency *)

open Message_templates

(** Eio sink signature Note: Eio uses direct-style code, so these are
    synchronous operations designed to run within Eio fibers. *)
module type S = sig
  type t

  val emit : t -> Log_event.t -> unit
  (** Emit a log event to the sink *)

  val flush : t -> unit
  (** Flush any buffered output *)

  val close : t -> unit
  (** Close the sink and release resources *)
end

(** Convert a sync sink to an Eio-compatible sink *)
module Sync_to_eio (S : Sink.S) : S with type t = S.t = struct
  type t = S.t

  let emit t event = S.emit t event

  let flush t = S.flush t

  let close t = S.close t
end

(** Composite Eio sink for multiple sinks *)
type sink_fn =
  { emit_fn: Log_event.t -> unit
  ; flush_fn: unit -> unit
  ; close_fn: unit -> unit
  ; min_level: Level.t option }

(** Create a composite sink from a list of sink functions *)
let composite_sink (sinks : sink_fn list) : sink_fn =
  { emit_fn=
      (fun event ->
        let event_level = Log_event.get_level event in
        List.iter
          (fun sink ->
            match sink.min_level with
            | Some min_level when Level.compare event_level min_level < 0 ->
                () (* Skip - event level too low *)
            | _ -> sink.emit_fn event )
          sinks )
  ; flush_fn= (fun () -> List.iter (fun sink -> sink.flush_fn ()) sinks)
  ; close_fn= (fun () -> List.iter (fun sink -> sink.close_fn ()) sinks)
  ; min_level= None }
;;
