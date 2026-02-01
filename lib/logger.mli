(** Logger interface - main logging interface *)

(** Logger signature *)
module type S = sig
  type t
  
  (** Core write method *)
  val write : t -> ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit
  
  (** Level checking *)
  val is_enabled : t -> Level.t -> bool
  
  (** Convenience methods for each level *)
  val verbose : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val debug : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val information : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val warning : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val error : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val fatal : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  
  (** Context enrichment *)
  val for_context : t -> string -> Yojson.Safe.t -> t
  val with_enricher : t -> (Log_event.t -> Log_event.t) -> t
  
  (** Sub-loggers for specific source types *)
  val for_source : t -> string -> t
end

(** Enricher signature - adds properties to log events *)
module type ENRICHER = sig
  type t
  
  (** Enrich a log event by adding properties *)
  val enrich : t -> Log_event.t -> Log_event.t
end

(** Filter signature - determines if an event should be logged *)
module type FILTER = sig
  type t
  
  (** Return true if the event should be included *)
  val is_included : t -> Log_event.t -> bool
end

(** Logger implementation type *)
type logger_impl = {
  min_level : Level.t;
  sinks : Composite_sink.t;
  enrichers : (Log_event.t -> Log_event.t) list;
  filters : (Log_event.t -> bool) list;
  context_properties : (string * Yojson.Safe.t) list;
  source : string option;
}

(** Include the Logger module that satisfies the S signature *)
include S with type t = logger_impl

(** Create a logger with minimum level and sinks *)
val create : min_level:Level.t -> sinks:Composite_sink.t -> t

(** Helper to add a property enricher *)
val add_property : t -> string -> Yojson.Safe.t -> t

(** Helper to add a level filter *)
val add_min_level_filter : t -> Level.t -> t
