(** Global logger - static access like Serilog.Log

    Provides global access to a configured logger instance. All operations are
    no-ops if no logger has been configured.

    Example:
    {[
      Log.set_logger logger;
      Log.information "Application started" [("version", `String "1.0.0")]
    ]} *)

val set_logger : Logger.t -> unit
(** Set the global logger instance *)

val get_logger : unit -> Logger.t option
(** Get the current global logger (if set) *)

val close_and_flush : unit -> unit
(** Close and flush the global logger, clearing the reference *)

val is_enabled : Level.t -> bool
(** Check if a level is enabled on the global logger *)

val write :
  ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit
(** Write with explicit level to the global logger *)

(** {2 Level-specific methods} *)

val verbose : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val debug : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val information : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val warning : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val error : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val fatal : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val for_context : string -> Yojson.Safe.t -> Logger.t
(** Create contextual logger with property (does not modify global). Returns a
    dummy logger if none configured. *)

val for_source : string -> Logger.t
(** Create sub-logger for source (does not modify global). Returns a dummy
    logger if none configured. *)

val flush : unit -> unit
(** Flush the global logger *)

val close : unit -> unit
(** Close the global logger and clear the reference *)
