(** Null sink - discards all events (for testing/disabled logging) *)

type t = unit

val emit : t -> Log_event.t -> unit
(** Emit - does nothing *)

val flush : t -> unit
(** Flush - does nothing *)

val close : t -> unit
(** Close - does nothing *)

val create : unit -> t
(** Create a null sink *)
