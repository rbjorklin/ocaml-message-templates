(** Global logger - static access like Serilog.Log *)

val set_logger : Logger.t -> unit
(** Set the global logger *)

val get_logger : unit -> Logger.t option
(** Get the current global logger (if set) *)

val close_and_flush : unit -> unit
(** Close and flush the global logger *)

val is_enabled : Level.t -> bool
(** Check if a level is enabled *)

val write :
  ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit
(** Write with explicit level *)

val verbose : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
(** Level-specific methods *)

val debug : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val information : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val warning : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val error : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val fatal : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val for_context : string -> Yojson.Safe.t -> Logger.t
(** Create contextual logger with property (does not modify global) *)

val for_source : string -> Logger.t
(** Create sub-logger for source (does not modify global) *)

val flush : unit -> unit
(** Flush the global logger *)

val close : unit -> unit
(** Close the global logger *)
