(** Core types for Message Templates

    This module defines the fundamental types used throughout the message
    templates library for parsing and processing template strings. *)

(** Operators that control how values are formatted in templates *)
type operator =
  | Default  (** Default formatting (to_string for the type) *)
  | Structure  (** @ - Output as structured JSON *)
  | Stringify  (** $ - Convert to JSON string representation *)

(** A hole in a template represents a variable placeholder *)
type hole =
  { name: string  (** Variable name *)
  ; operator: operator  (** Formatting operator *)
  ; format: string option  (** Optional printf-style format specifier *)
  ; alignment: (bool * int) option
        (** Optional alignment (is_negative, width) *) }

(** A template part is either literal text or a variable hole *)
type template_part =
  | Text of string  (** Literal text content *)
  | Hole of hole  (** Variable placeholder *)

(** A parsed template is a list of parts *)
type parsed_template = template_part list

val string_of_operator : operator -> string
(** Convert operator to its string representation ("", "@", or "$") *)

val string_of_hole : hole -> string
(** Convert a hole back to its template syntax representation *)

val reconstruct_template : parsed_template -> string
(** Reconstruct a template string from parsed parts *)
