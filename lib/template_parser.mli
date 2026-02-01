(** Template parser using Angstrom *)

open Types

(** Parse a template string into a list of parts *)
val parse_template : string -> (parsed_template, string) result

(** Extract all hole names from a parsed template *)
val extract_holes : parsed_template -> hole list
