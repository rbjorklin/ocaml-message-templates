(** Filter predicates for log events *)

(** Filter function type *)
type t = Log_event.t -> bool

val level_filter : Level.t -> t
(** Filter by minimum level - events must be at least this level *)

val property_filter : string -> (Yojson.Safe.t -> bool) -> t
(** Filter by property value - event must have the property and pass the
    predicate *)

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
