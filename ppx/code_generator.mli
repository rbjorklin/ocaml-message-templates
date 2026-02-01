(** Code generator for template expansion *)

open Ppxlib
open Message_templates.Types

(** Build a format string for Printf from template parts *)
val build_format_string : parsed_template -> string

(** Convert a value to its Yojson representation based on type *)
val yojson_of_value : loc:Location.t -> expression -> core_type option -> expression

(** Apply operator-specific transformations *)
val apply_operator : loc:Location.t -> operator -> expression -> core_type option -> expression

(** Generate code for a template *)
val generate_template_code : loc:Location.t -> Scope_analyzer.scope -> parsed_template -> expression
