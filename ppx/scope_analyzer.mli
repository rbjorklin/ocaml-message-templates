(** Scope analysis for variable validation in templates *)

open Ppxlib

(** Type representing the scope context *)
type scope

(** Create an empty scope *)
val empty_scope : scope

(** Add a binding to the current scope *)
val add_binding : string -> core_type option -> scope -> scope

(** Push a new scope level *)
val push_scope : scope -> scope

(** Check if a variable exists in scope chain *)
val find_variable : scope -> string -> core_type option

(** Validate that a variable exists in scope, raising a compile error if not *)
val validate_variable : loc:Location.t -> scope -> string -> core_type option

(** Extract variable names from a pattern *)
val extract_pattern_names : pattern -> string list

(** Build scope from let bindings *)
val scope_from_let_bindings : value_binding list -> scope

(** Build scope from function parameters *)
val scope_from_params : pattern -> scope
