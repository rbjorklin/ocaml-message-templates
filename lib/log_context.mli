(** LogContext - ambient properties that flow across scopes

    Properties are stored per-domain using Domain.DLS, making this safe for use
    in multicore OCaml programs. Properties do NOT automatically flow between
    domains - use [export_context]/[import_context] for that. *)

val push_property : string -> Yojson.Safe.t -> unit
(** Push a property onto the context stack *)

val pop_property : unit -> unit
(** Pop the most recent property *)

val current_properties : unit -> (string * Yojson.Safe.t) list
(** Get all current context properties *)

val clear : unit -> unit
(** Clear all context properties *)

val with_property : string -> Yojson.Safe.t -> (unit -> 'a) -> 'a
(** Execute function with temporary property (auto-pops on exit) *)

val with_properties : (string * Yojson.Safe.t) list -> (unit -> 'a) -> 'a
(** Execute function with multiple temporary properties *)

val with_scope : (unit -> 'a) -> 'a
(** Create a scope that clears context on exit *)

val generate_correlation_id : unit -> string
(** Generate a new correlation ID (UUID-like format) *)

val push_correlation_id : string -> unit
(** Push a correlation ID onto the stack *)

val pop_correlation_id : unit -> unit
(** Pop the current correlation ID *)

val get_correlation_id : unit -> string option
(** Get the current correlation ID if any *)

val with_correlation_id : string -> (unit -> 'a) -> 'a
(** Execute function with a correlation ID (auto-pops on exit) *)

val with_correlation_id_auto : (unit -> 'a) -> 'a
(** Execute function with an auto-generated correlation ID *)

(** {2 Cross-Domain Context} *)

(** Opaque type for context that can be passed between domains *)
type cross_domain_context

val export_context : unit -> cross_domain_context
(** Serialize current context for cross-domain transfer *)

val import_context : cross_domain_context -> (unit -> 'a) -> 'a
(** Import context in a new domain *)
