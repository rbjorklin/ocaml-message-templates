(** JSON sink - outputs log events as pure CLEF/JSON format *)

type t

val emit : t -> Log_event.t -> unit
(** Emit a log event as JSON *)

val flush : t -> unit
(** Flush output *)

val close : t -> unit
(** Close the sink *)

val create : string -> t
(** Create a new JSON sink *)

val of_out_channel : out_channel -> t
(** Create a JSON sink from an existing output channel *)
