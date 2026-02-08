(** Template parser using Angstrom *)

val parse_template : string -> (Types.parsed_template, string) result
(** Parse a template string into a list of parts *)

val extract_holes : Types.parsed_template -> Types.hole list
(** Extract all hole names from a parsed template *)
