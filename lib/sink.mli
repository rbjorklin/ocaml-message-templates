(** Sink interface - writes log events to destinations *)

(** Sink signature *)
module type S = sig
  type t
  
  (** Emit a log event to the sink *)
  val emit : t -> Log_event.t -> unit
  
  (** Flush any buffered output *)
  val flush : t -> unit
  
  (** Close the sink and release resources *)
  val close : t -> unit
end
