(** Log event type - Immutable record representing a single log entry

    Log events are the core data structure passed through the logging pipeline.
    They contain all information about a logged message including timestamp,
    level, template, rendered message, properties, and optional exception info.
*)

(** The log event type (opaque) *)
type t

val create :
     ?timestamp:Ptime.t
  -> ?exception_info:exn
  -> ?correlation_id:string
  -> level:Level.t
  -> message_template:string
  -> rendered_message:string
  -> properties:(string * Yojson.Safe.t) list
  -> unit
  -> t
(** Create a new log event.

    @param timestamp Optional timestamp (defaults to current time)
    @param exception_info Optional exception that was raised
    @param correlation_id Optional correlation ID for distributed tracing
    @param level Severity level of the event
    @param message_template Original template string with placeholders
    @param rendered_message Fully formatted message string
    @param properties List of structured properties as JSON values *)

val to_yojson : t -> Yojson.Safe.t
(** Convert log event to Yojson structure. Output follows CLEF (Compact Log
    Event Format) with fields:
    - [@t]: RFC3339 timestamp
    - [@mt]: Message template
    - [@l]: Log level
    - [@m]: Rendered message
    - [CorrelationId]: Optional correlation ID
    - Additional custom properties *)

val to_json_string : t -> string
(** Optimized direct JSON string generation. This builds the JSON string
    directly using a Buffer, avoiding intermediate Yojson.Safe.t structures and
    allocations. Use this for better performance when serializing to sinks. *)

(** {2 Field Accessors} *)

val get_timestamp : t -> Ptime.t
(** Get the event timestamp *)

val get_level : t -> Level.t
(** Get the severity level *)

val get_message_template : t -> string
(** Get the original message template *)

val get_rendered_message : t -> string
(** Get the fully rendered message *)

val get_properties : t -> (string * Yojson.Safe.t) list
(** Get the structured properties list *)

val get_exception : t -> exn option
(** Get exception info if present *)

val get_correlation_id : t -> string option
(** Get correlation ID if present *)
