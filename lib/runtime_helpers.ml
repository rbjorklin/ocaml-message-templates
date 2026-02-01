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
  let result = ref template in
  List.iter
    (fun (name, value) ->
      let placeholder = "{" ^ name ^ "}" in
      let value_str = json_to_string value in
      result :=
        Str.global_replace (Str.regexp_string placeholder) value_str !result )
    properties;
  !result
;;

(** Safe conversion using polymorphic comparison and type-specific functions.

    This module provides a safer alternative to the Obj-based runtime type
    detection. It uses a combination of: 1. Type-specific conversion functions
    for known types 2. Polymorphic comparison for basic type detection 3.
    Explicit type witnesses passed by caller

    Note: This is less precise than Obj but much safer and doesn't rely on
    compiler implementation details. *)
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

(* NOTE: The following functions use the unsafe Obj module and are kept for
   backward compatibility. New code should use the Safe_conversions module or
   specific conversion functions like string_to_json, int_to_json, etc. *)

let rec to_string : 'a. 'a -> string =
 fun v ->
  let repr = Obj.repr v in
  if Obj.is_int repr then
    string_of_int (Obj.obj repr)
  else if Obj.is_block repr then
    let tag = Obj.tag repr in
    if tag = 252 then (* string tag *)
      (Obj.obj repr : string)
    else if tag = 253 then (* float tag *)
      string_of_float (Obj.obj repr)
    else if tag = 254 then (* float array tag *)
      "<float array>"
    else if tag = 255 then (* custom tag *)
      "<custom>"
    else
      (* Regular block - could be a list, tuple, etc. *)
      let size = Obj.size repr in
      if size = 0 then
        "()"
      else
        let elems = Array.init size (fun i -> to_string (Obj.field repr i)) in
        "[" ^ String.concat "; " (Array.to_list elems) ^ "]"
  else
    "<unknown>"
;;

let to_json : 'a. 'a -> Yojson.Safe.t =
 fun v ->
  let repr = Obj.repr v in
  if Obj.is_int repr then
    (* In OCaml, bool is represented as int: false = 0, true = 1 *)
    let int_val = Obj.obj repr in
    if int_val = 0 then
      `Bool false
    else if int_val = 1 then
      `Bool true
    else
      `Int int_val
  else if Obj.is_block repr then
    let tag = Obj.tag repr in
    if tag = 252 then (* string tag *)
      `String (Obj.obj repr)
    else if tag = 253 then (* float tag *)
      `Float (Obj.obj repr)
    else
      `String (to_string v)
  else
    `String "<unknown>"
;;
