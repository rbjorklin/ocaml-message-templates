(** Lwt sink interface - async sink signatures for Lwt *)

open Message_templates

(** Lwt sink signature *)
module type S = sig
  type t

  val emit : t -> Log_event.t -> unit Lwt.t
  (** Emit a log event to the sink *)

  val flush : t -> unit Lwt.t
  (** Flush any buffered output *)

  val close : t -> unit Lwt.t
  (** Close the sink and release resources *)
end

(** Convert a sync sink to an Lwt sink *)
module Sync_to_lwt (S : Sink.S) : S with type t = S.t = struct
  type t = S.t

  let emit t event = Lwt.return (S.emit t event)

  let flush t = Lwt.return (S.flush t)

  let close t = Lwt.return (S.close t)
end

(** Composite Lwt sink for multiple sinks *)
type sink_fn =
  { emit_fn: Log_event.t -> unit Lwt.t
  ; flush_fn: unit -> unit Lwt.t
  ; close_fn: unit -> unit Lwt.t
  ; min_level: Level.t option }

(** Create a composite sink from a list of sink functions *)
let composite_sink (sinks : sink_fn list) : sink_fn =
  { emit_fn=
      (fun event ->
        let open Lwt.Syntax in
        let event_level = Log_event.get_level event in
        let* _ =
          Lwt_list.iter_p
            (fun sink ->
              match sink.min_level with
              | Some min_level when Level.compare event_level min_level < 0 ->
                  Lwt.return () (* Skip - event level too low *)
              | _ -> sink.emit_fn event )
            sinks
        in
        Lwt.return () )
  ; flush_fn=
      (fun () ->
        let open Lwt.Syntax in
        let* _ = Lwt_list.iter_p (fun sink -> sink.flush_fn ()) sinks in
        Lwt.return () )
  ; close_fn=
      (fun () ->
        let open Lwt.Syntax in
        let* _ = Lwt_list.iter_p (fun sink -> sink.close_fn ()) sinks in
        Lwt.return () )
  ; min_level= None }
;;
