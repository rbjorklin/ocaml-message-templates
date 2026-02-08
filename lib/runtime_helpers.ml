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

(** Render a template by replacing {var} placeholders with values from properties *)
let render_template template properties =
  List.fold_left
    (fun acc (name, value) ->
      let placeholder = "{" ^ name ^ "}" in
      let value_str = json_to_string value in
      Str.global_replace (Str.regexp_string placeholder) value_str acc )
    template properties
;;

(** Safe conversion using explicit type witnesses.

    This module provides type-specific conversion functions. For best results,
    use explicit type annotations in your templates. *)
module Safe_conversions = struct
  type 'a t = 'a -> Yojson.Safe.t

  (** Create a type-specific conversion *)
  let make : 'a. ('a -> Yojson.Safe.t) -> 'a t = fun f -> f

  (** Common conversions *)
  let string : string t = make string_to_json

  let int : int t = make int_to_json

  let float : float t = make float_to_json

  let bool : bool t = make bool_to_json

  let int64 : int64 t = make int64_to_json

  let int32 : int32 t = make int32_to_json

  let nativeint : nativeint t = make nativeint_to_json

  let char : char t = make char_to_json

  let unit : unit t = make unit_to_json

  let list : 'a. 'a t -> 'a list t = fun f -> make (list_to_json f)

  let array : 'a. 'a t -> 'a array t = fun f -> make (array_to_json f)

  let option : 'a. 'a t -> 'a option t = fun f -> make (option_to_json f)
end

(** Generic value to string conversion using Obj module. This is used as a
    fallback when type information is not available at compile time. NOTE: This
    uses Obj for runtime type inspection. For production use, prefer explicit
    type annotations. *)
let generic_to_string (type a) (v : a) : string =
  let module O = Obj in
  (* Recursively convert a list to string representation *)
  let rec list_to_string lst =
    let repr = O.repr lst in
    if O.is_int repr then
      (* Empty list *)
      "[]"
    else if O.is_block repr && O.tag repr = 0 then
      (* Non-empty list: block with tag 0, containing pair (head, tail) *)
      let head = O.field repr 0 in
      let tail = O.field repr 1 in
      let head_str = generic_to_string_impl head in
      let tail_str = list_contents_to_string tail in
      "[" ^ head_str ^ tail_str ^ "]"
    else
      "<unknown-list>"
  and list_contents_to_string lst =
    let repr = O.repr lst in
    if O.is_int repr then
      (* End of list *)
      ""
    else if O.is_block repr && O.tag repr = 0 then
      (* More elements *)
      let head = O.field repr 0 in
      let tail = O.field repr 1 in
      let head_str = generic_to_string_impl head in
      "; " ^ head_str ^ list_contents_to_string tail
    else
      ""
  and generic_to_string_impl repr =
    if O.is_int repr then
      string_of_int (O.obj repr)
    else if O.is_block repr then
      match
        O.tag repr
      with
      | 252 -> (O.obj repr : string)
      | 253 -> string_of_float (O.obj repr : float)
      | 0 ->
          (* Could be a list or a tuple - check if it looks like a cons cell *)
          if O.size repr = 2 then
            (* Might be a list cons cell, try to convert as list *)
            list_to_string (O.obj repr)
          else
            "<block>"
      | _ -> "<unknown>"
    else
      "<unknown>"
  in
  generic_to_string_impl (O.repr v)
;;

(** Generic value to JSON conversion. This is a best-effort conversion for
    unknown types. *)
let generic_to_json (type a) (v : a) : Yojson.Safe.t =
  let module O = Obj in
  let repr = O.repr v in
  if O.is_int repr then
    `Int (O.obj repr)
  else if O.is_block repr then
    match
      O.tag repr
    with
    | 252 -> `String (O.obj repr : string)
    | 253 -> `Float (O.obj repr : float)
    | _ -> `String (generic_to_string v)
  else
    `String "<unknown>"
;;

(** Format a timestamp for display *)
let format_timestamp tm = Ptime.to_rfc3339 tm

(** Format a template string for sink output.
    Replaces {timestamp}, {level}, and {message} placeholders. *)
let format_sink_template template event =
  let timestamp_str = format_timestamp (Log_event.get_timestamp event) in
  let level_str = Level.to_short_string (Log_event.get_level event) in
  let message_str = Log_event.get_rendered_message event in
  template
  |> Str.global_replace (Str.regexp "{timestamp}") timestamp_str
  |> Str.global_replace (Str.regexp "{level}") level_str
  |> Str.global_replace (Str.regexp "{message}") message_str
;;
