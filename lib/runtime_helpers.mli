(** Runtime type conversions using Obj module introspection

    This module provides runtime type conversions between OCaml values and JSON
    representations. All template variables use the generic conversion functions
    which inspect values at runtime using the Obj module. *)

(** {2 JSON Extraction} *)

val json_to_string : Yojson.Safe.t -> string
(** Extract string value from Yojson.t, converting if necessary *)

(** {2 Template Rendering} *)

val render_template : string -> (string * Yojson.Safe.t) list -> string
(** Render a template by replacing [{var}] placeholders with values from
    properties *)

(** {2 Generic Conversions} *)

val generic_to_string : 'a -> string
(** Generic value to string conversion using Obj module. This is used as a
    fallback when type information is not available at compile time. NOTE: Uses
    Obj for runtime type inspection. For production use, prefer explicit type
    annotations. *)

val generic_to_json : 'a -> Yojson.Safe.t
(** Generic value to JSON conversion. This is a best-effort conversion for
    unknown types. *)

(** {2 Sink Formatting} *)

val format_timestamp : Ptime.t -> string
(** Format a timestamp for display as RFC3339 *)

val get_current_timestamp_rfc3339 : unit -> string
(** Get current timestamp as RFC3339 string - optimized for frequent calls *)

val format_sink_template : string -> Log_event.t -> string
(** Format a template string for sink output. Replaces [{timestamp}], [{level}],
    and [{message}] placeholders. *)

val replace_all : string -> string -> string -> string
(** Replace all occurrences of a pattern in a template with a replacement.
    [replace_all template pattern replacement] scans [template] and replaces all
    occurrences of [pattern] with [replacement]. Optimized single-pass
    implementation using Buffer. *)
