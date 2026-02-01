(** Sink interface - writes log events to destinations *)

(** Sink signature *)
module type S = sig
  type t

  val emit : t -> Log_event.t -> unit
  (** Emit a log event to the sink *)

  val flush : t -> unit
  (** Flush any buffered output *)

  val close : t -> unit
  (** Close the sink and release resources *)
end
