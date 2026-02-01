(** Null sink - discards all events (for testing/disabled logging) *)

type t = unit

(** Emit - does nothing *)
let emit () _event = ()

(** Flush - does nothing *)
let flush () = ()

(** Close - does nothing *)
let close () = ()

(** Create a null sink *)
let create () = ()
