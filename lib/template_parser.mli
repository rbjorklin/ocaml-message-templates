(** Template parser using Angstrom *)

open Types

val parse_template : string -> (parsed_template, string) result
(** Parse a template string into a list of parts *)

val extract_holes : parsed_template -> hole list
(** Extract all hole names from a parsed template *)
