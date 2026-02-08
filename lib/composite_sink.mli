(** Composite sink - routes log events to multiple sinks *)

type sink_fn =
  { emit_fn: Log_event.t -> unit
  ; flush_fn: unit -> unit
  ; close_fn: unit -> unit }

type t = sink_fn list

val emit : t -> Log_event.t -> unit
(** Emit to all sinks *)

val flush : t -> unit
(** Flush all sinks *)

val close : t -> unit
(** Close all sinks *)

val create : sink_fn list -> t
(** Create a composite sink from sink functions *)
