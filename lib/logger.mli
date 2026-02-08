(** Logger interface - main logging interface *)

(** Logger signature *)
module type S = sig
  type t

  val write :
    t -> ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit
  (** Core write method *)

  val is_enabled : t -> Level.t -> bool
  (** Level checking *)

  val verbose : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  (** Convenience methods for each level *)

  val debug : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val information :
    t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val warning : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val error : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val fatal : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val for_context : t -> string -> Yojson.Safe.t -> t
  (** Context enrichment *)

  val with_enricher : t -> (Log_event.t -> Log_event.t) -> t

  val for_source : t -> string -> t
  (** Sub-loggers for specific source types *)

  val flush : t -> unit
  (** Flush all sinks *)

  val close : t -> unit
  (** Close all sinks *)
end

(** Enricher signature - adds properties to log events *)
module type ENRICHER = sig
  type t

  val enrich : t -> Log_event.t -> Log_event.t
  (** Enrich a log event by adding properties *)
end

(** Filter signature - determines if an event should be logged *)
module type FILTER = sig
  type t

  val is_included : t -> Log_event.t -> bool
  (** Return true if the event should be included *)
end

(** Logger type - opaque *)
type t

(** {2 Core Functions} *)

val create :
  min_level:Level.t -> sinks:(Composite_sink.sink_fn * Level.t option) list -> t
(** Create a logger with minimum level and sinks (with optional per-sink level
    filtering) *)

val write :
  t -> ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit
(** Core write method *)

val is_enabled : t -> Level.t -> bool
(** Check if a level is enabled *)

(** {2 Level-specific Methods} *)

val verbose : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val debug : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val information :
  t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val warning : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val error : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

val fatal : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

(** {2 Context and Enrichment} *)

val for_context : t -> string -> Yojson.Safe.t -> t
(** Create a contextual logger with additional property *)

val with_enricher : t -> (Log_event.t -> Log_event.t) -> t
(** Add an enricher function *)

val for_source : t -> string -> t
(** Create a sub-logger for a specific source *)

(** {2 Lifecycle} *)

val flush : t -> unit
(** Flush all sinks *)

val close : t -> unit
(** Close all sinks *)

(** {2 Helper Functions} *)

val add_property : t -> string -> Yojson.Safe.t -> t
(** Helper to add a property enricher - alias for for_context *)

val add_min_level_filter : t -> Level.t -> t
(** Helper to add a minimum level filter *)

val add_filter : t -> (Log_event.t -> bool) -> t
(** Add a custom filter function *)
