(** Safe runtime conversions for Message Templates

    This module provides type-safe conversions between OCaml values and JSON
    representations. It includes both specific type converters and a
    Safe_conversions module for composable conversions. *)

(** {2 Basic Type Conversions} *)

val string_to_json : string -> Yojson.Safe.t
(** Convert a string to Yojson.Safe.t *)

val int_to_json : int -> Yojson.Safe.t
(** Convert an int to Yojson.Safe.t *)

val float_to_json : float -> Yojson.Safe.t
(** Convert a float to Yojson.Safe.t *)

val bool_to_json : bool -> Yojson.Safe.t
(** Convert a bool to Yojson.Safe.t *)

val int64_to_json : int64 -> Yojson.Safe.t
(** Convert an int64 to Yojson.Safe.t (as Intlit) *)

val int32_to_json : int32 -> Yojson.Safe.t
(** Convert an int32 to Yojson.Safe.t (as Intlit) *)

val nativeint_to_json : nativeint -> Yojson.Safe.t
(** Convert a nativeint to Yojson.Safe.t (as Intlit) *)

val char_to_json : char -> Yojson.Safe.t
(** Convert a char to Yojson.Safe.t (as single-character string) *)

val unit_to_json : unit -> Yojson.Safe.t
(** Convert a unit value to Yojson.Safe.t (as Null) *)

(** {2 Collection Conversions} *)

val list_to_json : ('a -> Yojson.Safe.t) -> 'a list -> Yojson.Safe.t
(** Convert a list using a conversion function *)

val array_to_json : ('a -> Yojson.Safe.t) -> 'a array -> Yojson.Safe.t
(** Convert an array using a conversion function *)

val option_to_json : ('a -> Yojson.Safe.t) -> 'a option -> Yojson.Safe.t
(** Convert an option using a conversion function (None -> Null) *)

val result_to_json :
     ('a -> Yojson.Safe.t)
  -> ('e -> Yojson.Safe.t)
  -> ('a, 'e) result
  -> Yojson.Safe.t
(** Convert a result using conversion functions for both cases *)

val pair_to_json :
  ('a -> Yojson.Safe.t) -> ('b -> Yojson.Safe.t) -> 'a * 'b -> Yojson.Safe.t
(** Convert a pair using conversion functions *)

val triple_to_json :
     ('a -> Yojson.Safe.t)
  -> ('b -> Yojson.Safe.t)
  -> ('c -> Yojson.Safe.t)
  -> 'a * 'b * 'c
  -> Yojson.Safe.t
(** Convert a triple using conversion functions *)

(** {2 JSON Extraction} *)

val json_to_string : Yojson.Safe.t -> string
(** Extract string value from Yojson.t, converting if necessary *)

(** {2 Template Rendering} *)

val render_template : string -> (string * Yojson.Safe.t) list -> string
(** Render a template by replacing {var} placeholders with values from properties *)

(** {2 Safe Conversions Module} *)

(** Composable type-safe conversions without Obj module usage.

    This module provides a type-safe way to build converters for complex types
    by composing simple ones. Use these converters when you know the type at
    compile time.

    Example:
    {[
      let convert = Safe_conversions.(list (pair int string))

      let json = convert [(1, "a"); (2, "b")]
    ]} *)
module Safe_conversions : sig
  (** Type of a conversion function from 'a to JSON *)
  type 'a t

  val make : ('a -> Yojson.Safe.t) -> 'a t
  (** Create a type-specific conversion *)

  val string : string t

  val int : int t

  val float : float t

  val bool : bool t

  val int64 : int64 t

  val int32 : int32 t

  val nativeint : nativeint t

  val char : char t

  val unit : unit t

  val list : 'a t -> 'a list t

  val array : 'a t -> 'a array t

  val option : 'a t -> 'a option t
end

(** {2 Runtime Type-Agnostic Conversions}

    These functions use the Obj module for runtime type inspection. They are
    primarily used by the PPX as a fallback when type information is not
    available at compile time. For new code, prefer explicit type annotations
    and the Safe_conversions module. *)

val any_to_string : 'a -> string
(** Convert a value of unknown type to string (uses Obj module for runtime type
    detection). Use explicit type annotations when possible. *)

val any_to_json : 'a -> Yojson.Safe.t
(** Convert a value of unknown type to JSON (uses Obj module for runtime type
    detection). Use explicit type annotations when possible. This is the primary
    fallback used by the PPX when compile-time type information is unavailable.
*)

val to_string : 'a -> string
(** Alias for any_to_string *)

val to_json : 'a -> Yojson.Safe.t
(** Alias for any_to_json *)
