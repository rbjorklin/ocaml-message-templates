(** Filter predicates for log events

    Filters allow you to control which log events are emitted based on various
    criteria such as log level, property values, or custom predicates.

    Example:
    {[
      let filter =
        Filter.(level_filter Level.Warning |> all [matching "user_id"])
          Logger.create ~min_level:Level.Debug ~filters:[filter]
      ;;
    ]} *)

(** Filter function type - returns true if event should be included *)
type t = Log_event.t -> bool

val level_filter : Level.t -> t
(** Filter by minimum level - events must be at least this level *)

val property_filter : string -> (Yojson.Safe.t -> bool) -> t
(** Filter by property value. Event must have the property and the predicate
    must return true. *)

val matching : string -> t
(** Filter that matches if a property name exists (regardless of value) *)

val all : t list -> t
(** Combine multiple filters with AND logic - all must pass *)

val any : t list -> t
(** Combine multiple filters with OR logic - any can pass *)

val not_filter : t -> t
(** Negate a filter *)

val always_pass : t
(** Always include filter - passes everything *)

val always_block : t
(** Always exclude filter - blocks everything *)
