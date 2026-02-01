(** Null sink - discards all events (for testing/disabled logging)

    The null sink is useful for:
    - Disabling logging in production by configuration
    - Testing scenarios where log output should be suppressed
    - Performance benchmarking to measure logging overhead *)

(** Null sink type (unit - carries no state) *)
type t = unit

val emit : t -> Log_event.t -> unit
(** Emit - does nothing (discards all events) *)

val flush : t -> unit
(** Flush - does nothing *)

val close : t -> unit
(** Close - does nothing *)

val create : unit -> t
(** Create a null sink *)
