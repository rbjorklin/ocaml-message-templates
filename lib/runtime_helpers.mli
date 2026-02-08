(** Safe runtime conversions for Message Templates

    This module provides type-safe conversions between OCaml values and JSON
    representations. It includes both specific type converters and a Converter
    module for composable conversions.

    {b Migration from Obj-based conversions:} Previously, this module provided
    [generic_to_string] and [generic_to_json] which used the Obj module for
    runtime type inspection. These are now deprecated. Use the [Converter]
    module or explicit type annotations instead. *)

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
(** Render a template by replacing [{var}] placeholders with values from
    properties *)

(** {2 Converter Module}

    Composable type-safe conversions without Obj module usage.

    This module provides a type-safe way to build converters for complex types
    by composing simple ones. Use these converters when you know the type at
    compile time.

    Example:
    {[
      type user = { id : int; name : string }

      let user_to_json u =
        `Assoc [("id", `Int u.id); ("name", `String u.name)]

      let user = { id = 42; name = "Alice" } in
      Log.information "User {user}" [("user", user_to_json user)]
    ]}

    Or with the PPX and a type annotation:
    {[
      let (user : user) = {id= 42; name= "Alice"}

      let _, json = [%template "User {user}"]
      (* Uses user_to_json from scope based on type annotation *)
    ]} *)
module Converter : sig
  (** Type of a converter function from 'a to JSON *)
  type 'a t = 'a -> Yojson.Safe.t

  val make : ('a -> Yojson.Safe.t) -> 'a t
  (** Create a type-specific conversion *)

  val string : string t
  (** String converter *)

  val int : int t
  (** Int converter *)

  val float : float t
  (** Float converter *)

  val bool : bool t
  (** Bool converter *)

  val int64 : int64 t
  (** Int64 converter (as Intlit) *)

  val int32 : int32 t
  (** Int32 converter (as Intlit) *)

  val nativeint : nativeint t
  (** Nativeint converter (as Intlit) *)

  val char : char t
  (** Char converter (as single-character string) *)

  val unit : unit t
  (** Unit converter (as Null) *)

  val list : 'a t -> 'a list t
  (** List converter using element converter *)

  val array : 'a t -> 'a array t
  (** Array converter using element converter *)

  val option : 'a t -> 'a option t
  (** Option converter using element converter (None -> Null) *)

  val result : 'a t -> 'b t -> ('a, 'b) result t
  (** Result converter using converters for Ok and Error *)

  val pair : 'a t -> 'b t -> ('a * 'b) t
  (** Pair converter using element converters *)

  val triple : 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t
  (** Triple converter using element converters *)
end

(** {2 Deprecated: Safe_conversions Module} *)

(** Safe_conversions is now an alias for Converter.
    @deprecated Use the [Converter] module instead *)
module Safe_conversions = Converter

(** {2 Deprecated: Generic Conversions}

    These functions previously used the Obj module for runtime type inspection.
    They are now deprecated and return placeholder values. Use explicit type
    annotations and the Converter module instead. *)

val generic_to_string : 'a -> string
[@@ocaml.deprecated
  "Use explicit type annotations or the Converter module. This function previously used Obj for runtime type inspection."]
(** DEPRECATED: Generic value to string conversion. Previously used Obj module.
    Now returns a placeholder message. Use explicit converters instead. *)

val generic_to_json : 'a -> Yojson.Safe.t
[@@ocaml.deprecated
  "Use explicit type annotations or the Converter module. This function previously used Obj for runtime type inspection."]
(** DEPRECATED: Generic value to JSON conversion. Previously used Obj module.
    Now returns a placeholder. Use explicit converters instead. *)

(** {2 Sink Formatting} *)

val format_timestamp : Ptime.t -> string
(** Format a timestamp for display as RFC3339 *)

val get_current_timestamp_rfc3339 : unit -> string
(** Get current timestamp as RFC3339 string - optimized for frequent calls *)

val format_sink_template : string -> Log_event.t -> string
(** Format a template string for sink output. Replaces [{timestamp}], [{level}],
    and [{message}] placeholders. *)

val replace_all : string -> string -> string -> string
(** Replace all occurrences of a pattern in a template with a replacement.
    [replace_all template pattern replacement] scans [template] and replaces all
    occurrences of [pattern] with [replacement]. Optimized single-pass
    implementation using Buffer. *)
