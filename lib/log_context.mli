(** LogContext - Ambient properties that flow across async boundaries

    This module provides a thread-local context for storing properties that
    should be included with all log events within a scope.

    Typical usage:
    {[
      Log_context.with_property "user_id" (`String user_id) (fun () ->
          Logger.information logger "User action" []
          (* All log events within this scope will include user_id *) )
    ]} *)

val push_property : string -> Yojson.Safe.t -> unit
(** Push a property onto the context stack. The property will be included in all
    subsequent log events. *)

val pop_property : unit -> unit
(** Pop the most recent property from the context stack. *)

val current_properties : unit -> (string * Yojson.Safe.t) list
(** Get all current context properties as an associative list. *)

val clear : unit -> unit
(** Clear all context properties. Use with caution. *)

val with_property : string -> Yojson.Safe.t -> (unit -> 'a) -> 'a
(** Execute a function with a temporary property. The property is automatically
    removed when the function completes or raises an exception. *)

val with_properties : (string * Yojson.Safe.t) list -> (unit -> 'a) -> 'a
(** Execute a function with multiple temporary properties. *)

val with_scope : (unit -> 'a) -> 'a
(** Create a scope that preserves the previous context state. All context
    modifications within the scope are reverted on exit. *)

(** {2 Correlation ID Support} *)

val get_correlation_id : unit -> string option
(** Get the current correlation ID if one is set. *)

val with_correlation_id : string -> (unit -> 'a) -> 'a
(** Execute a function with a correlation ID. The ID will be automatically
    included in all log events. Example:
    [with_correlation_id "req-123" (fun () -> ...)] *)

val with_correlation_id_auto : (unit -> 'a) -> 'a
(** Execute a function with an auto-generated correlation ID. The ID is
    generated in UUID-like format (e.g., "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
*)
