(** Scope analysis for variable validation in templates *)

open Ppxlib

(** Type representing the scope context *)
type scope

val empty_scope : scope
(** Create an empty scope *)

val add_binding : string -> core_type option -> scope -> scope
(** Add a binding to the current scope *)

val push_scope : scope -> scope
(** Push a new scope level *)

val find_variable : scope -> string -> core_type option
(** Check if a variable exists in scope chain *)

val validate_variable : loc:Location.t -> scope -> string -> core_type option
(** Validate that a variable exists in scope, raising a compile error if not *)

val extract_pattern_names : pattern -> string list
(** Extract variable names from a pattern *)

val scope_from_let_bindings : value_binding list -> scope
(** Build scope from let bindings *)

val scope_from_params : pattern -> scope
(** Build scope from function parameters *)
