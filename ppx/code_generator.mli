(** Code generator for template expansion *)

open Ppxlib
open Message_templates.Types

val build_format_string : parsed_template -> string
(** Build a format string for Printf from template parts *)

val yojson_of_value :
  loc:Location.t -> expression -> core_type option -> expression
(** Convert a value to its Yojson representation based on type *)

val apply_operator :
  loc:Location.t -> operator -> expression -> core_type option -> expression
(** Apply operator-specific transformations *)

val generate_template_code :
  loc:Location.t -> Scope_analyzer.scope -> parsed_template -> expression
(** Generate code for a template *)
