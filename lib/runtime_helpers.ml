(** Safe runtime conversions without Obj module usage *)

(** Convert a string to Yojson.Safe.t *)
let string_to_json s = `String s

(** Convert an int to Yojson.Safe.t *)
let int_to_json i = `Int i

(** Convert a float to Yojson.Safe.t *)
let float_to_json f = `Float f

(** Convert a bool to Yojson.Safe.t *)
let bool_to_json b = `Bool b

(** Convert an int64 to Yojson.Safe.t *)
let int64_to_json i = `Intlit (Int64.to_string i)

(** Convert an int32 to Yojson.Safe.t *)
let int32_to_json i = `Intlit (Int32.to_string i)

(** Convert a nativeint to Yojson.Safe.t *)
let nativeint_to_json i = `Intlit (Nativeint.to_string i)

(** Convert a char to Yojson.Safe.t *)
let char_to_json c = `String (String.make 1 c)

(** Convert a unit value to Yojson.Safe.t *)
let unit_to_json () = `Null

(** Convert a list using a conversion function *)
let list_to_json f lst = `List (List.map f lst)

(** Convert an array using a conversion function *)
let array_to_json f arr = `List (Array.to_list (Array.map f arr))

(** Convert an option using a conversion function *)
let option_to_json f = function
  | None -> `Null
  | Some v -> f v
;;

(** Convert a result using conversion functions *)
let result_to_json f_ok f_err = function
  | Ok v -> `Assoc [("Ok", f_ok v)]
  | Error e -> `Assoc [("Error", f_err e)]
;;

(** Convert a pair using conversion functions *)
let pair_to_json f1 f2 (a, b) = `List [f1 a; f2 b]

(** Convert a triple using conversion functions *)
let triple_to_json f1 f2 f3 (a, b, c) = `List [f1 a; f2 b; f3 c]

(** Extract string value from Yojson.t, converting if necessary *)
let json_to_string = function
  | `String s -> s
  | `Int i -> string_of_int i
  | `Float f -> string_of_float f
  | `Bool b -> string_of_bool b
  | `Null -> "null"
  | _ -> "<complex>"
;;

(** Replace all occurrences of a pattern in a string with a replacement. *)
let replace_all template pattern replacement =
  let pattern_len = String.length pattern in
  let template_len = String.length template in
  if pattern_len = 0 then
    template
  else
    let buf = Buffer.create (template_len + 100) in
    let rec scan i =
      if i > template_len - pattern_len then
        Buffer.add_substring buf template i (template_len - i)
      else if String.sub template i pattern_len = pattern then (
        Buffer.add_string buf replacement;
        scan (i + pattern_len) )
      else (
        Buffer.add_char buf template.[i];
        scan (i + 1) )
    in
    scan 0; Buffer.contents buf
;;

(** Render a template by replacing var placeholders with values from properties.
*)
let render_template template properties =
  List.fold_left
    (fun acc (name, value) ->
      let placeholder = "{" ^ name ^ "}" in
      let value_str = json_to_string value in
      replace_all acc placeholder value_str )
    template properties
;;

(** Converter module for explicit type-safe conversions.

    This module provides type-safe converters that can be used with the PPX or
    directly with the Log module. Use these when you have types that aren't
    automatically handled by the PPX.

    Example:
    {[
      type user = { id : int; name : string }

      let user_to_json u =
        `Assoc [("id", `Int u.id); ("name", `String u.name)]

      let user = { id = 42; name = "Alice" } in
      Log.information "User {user}" [("user", user_to_json user)]
    ]} *)
module Converter = struct
  (** Type of a converter function *)
  type 'a t = 'a -> Yojson.Safe.t

  (** Create a custom converter *)
  let make : 'a. ('a -> Yojson.Safe.t) -> 'a t = fun f -> f

  (** Convert a string to JSON *)
  let string : string t = make string_to_json

  (** Convert an int to JSON *)
  let int : int t = make int_to_json

  (** Convert a float to JSON *)
  let float : float t = make float_to_json

  (** Convert a bool to JSON *)
  let bool : bool t = make bool_to_json

  (** Convert an int64 to JSON *)
  let int64 : int64 t = make int64_to_json

  (** Convert an int32 to JSON *)
  let int32 : int32 t = make int32_to_json

  (** Convert a nativeint to JSON *)
  let nativeint : nativeint t = make nativeint_to_json

  (** Convert a char to JSON *)
  let char : char t = make char_to_json

  (** Convert unit to JSON *)
  let unit : unit t = make unit_to_json

  (** Convert a list using an element converter *)
  let list : 'a. 'a t -> 'a list t =
   fun elem_conv -> make (list_to_json elem_conv)
  ;;

  (** Convert an array using an element converter *)
  let array : 'a. 'a t -> 'a array t =
   fun elem_conv -> make (array_to_json elem_conv)
  ;;

  (** Convert an option using an element converter *)
  let option : 'a. 'a t -> 'a option t =
   fun elem_conv -> make (option_to_json elem_conv)
  ;;

  (** Convert a result using converters for Ok and Error *)
  let result : 'a 'b. 'a t -> 'b t -> ('a, 'b) result t =
   fun ok_conv err_conv -> make (result_to_json ok_conv err_conv)
  ;;

  (** Convert a pair using element converters *)
  let pair : 'a 'b. 'a t -> 'b t -> ('a * 'b) t =
   fun a_conv b_conv -> make (pair_to_json a_conv b_conv)
  ;;

  (** Convert a triple using element converters *)
  let triple : 'a 'b 'c. 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t =
   fun a_conv b_conv c_conv -> make (triple_to_json a_conv b_conv c_conv)
  ;;
end

(** Legacy Safe_conversions module - now an alias for Converter
    @deprecated Use the [Converter] module instead *)
module Safe_conversions = Converter

(** DEPRECATED: Use the Converter module instead. This function previously used
    Obj for runtime type inspection. It now returns a placeholder message. *)
let generic_to_string _v = "<deprecated: use explicit converters>"

(** DEPRECATED: Use the Converter module instead. This function previously used
    Obj for runtime type inspection. It now returns a placeholder JSON value. *)
let generic_to_json _v = `String "<deprecated: use explicit converters>"

(** Format a timestamp for display *)
let format_timestamp tm = Ptime.to_rfc3339 tm

(** Get current timestamp as RFC3339 string. *)
let get_current_timestamp_rfc3339 () = Timestamp_cache.get_rfc3339 ()

(** Format a template string for sink output. *)
let format_sink_template template event =
  let timestamp_str = format_timestamp (Log_event.get_timestamp event) in
  let level_str = Level.to_short_string (Log_event.get_level event) in
  let message_str = Log_event.get_rendered_message event in
  let with_timestamp = replace_all template "{timestamp}" timestamp_str in
  let with_level = replace_all with_timestamp "{level}" level_str in
  replace_all with_level "{message}" message_str
;;
