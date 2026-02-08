(** Core types for Message Templates *)

type operator =
  | Default
  | Structure
  | Stringify

type hole =
  { name: string
  ; operator: operator
  ; format: string option
  ; alignment: (bool * int) option  (** (is_negative, width) *) }

type template_part =
  | Text of string
  | Hole of hole

type parsed_template = template_part list

(** Property type for log events: name-value pair with JSON value *)
type property = string * Yojson.Safe.t

(** List of properties *)
type property_list = property list

val string_of_operator : operator -> string
(** Convert operator to string for debugging *)

val string_of_hole : hole -> string
(** Convert a hole to string representation *)

val reconstruct_template : parsed_template -> string
(** Reconstruct a template from parsed parts *)
