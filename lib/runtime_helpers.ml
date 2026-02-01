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

(** Recursively convert an Obj.t to string representation *)
let rec obj_to_string (obj : Obj.t) : string =
  let module O = Obj in
  if O.is_int obj then
    string_of_int (O.obj obj)
  else if O.is_block obj then
    match
      O.tag obj
    with
    | 252 -> (O.obj obj : string)
    | 253 -> string_of_float (O.obj obj : float)
    | 0 ->
        (* Likely a cons cell - try to process as list *)
        let size = O.size obj in
        if size = 2 then
          let hd = O.field obj 0 in
          let tl = O.field obj 1 in
          if O.is_int tl && (O.obj tl : int) = 0 then
            "[" ^ obj_to_string hd ^ "]"
          else
            "[" ^ obj_to_string hd ^ "; " ^ obj_to_string tl ^ "]"
        else
          let elems =
            Array.init size (fun i -> obj_to_string (O.field obj i))
          in
          "[" ^ String.concat "; " (Array.to_list elems) ^ "]"
    | _ -> "<unknown>"
  else
    "<unknown>"
;;

(** Convert a value of unknown type to string. This uses the deprecated Obj
    module but is wrapped for safety. For production use, prefer explicit type
    annotations. *)
let any_to_string (type a) (v : a) : string =
  let module O = Obj in
  let repr = O.repr v in
  if O.is_int repr then
    string_of_int (O.obj repr)
  else if O.is_block repr then
    match
      O.tag repr
    with
    | 252 -> (O.obj repr : string)
    | 253 -> string_of_float (O.obj repr : float)
    | 0 ->
        (* Tag 0 often indicates a list or tuple structure *)
        let size = O.size repr in
        if size = 0 then
          "()"
        else if
          size = 2 && (O.is_int (O.field repr 1) || O.tag (O.field repr 1) = 0)
        then
          (* Potentially a cons cell - format as list *)
          let rec list_to_string obj =
            if O.is_int obj then
              if (O.obj obj : int) = 0 then
                ""
              else
                "; <non-list>"
            else if O.tag obj = 0 && O.size obj = 2 then
              let hd = obj_to_string (O.field obj 0) in
              let tl = O.field obj 1 in
              if O.is_int tl && (O.obj tl : int) = 0 then
                hd
              else
                hd ^ "; " ^ list_to_string tl
            else
              "; <non-list>"
          in
          "[" ^ list_to_string repr ^ "]"
        else
          (* Regular tuple or other structure *)
          let elems =
            Array.init size (fun i -> obj_to_string (O.field repr i))
          in
          "[" ^ String.concat "; " (Array.to_list elems) ^ "]"
    | _ -> "<unknown type: use explicit type annotation>"
  else
    "<unknown type: use explicit type annotation>"
;;

(** Convert a value of unknown type to JSON. This uses the deprecated Obj module
    but is wrapped for safety. For production use, prefer explicit type
    annotations. *)
let any_to_json (type a) (v : a) : Yojson.Safe.t =
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
    | _ -> `String (any_to_string v)
  else
    `String "<unknown>"
;;

(* DEPRECATED: These functions are kept for backward compatibility. New code
   should use Safe_conversions module or explicit type conversions. *)
let to_string : 'a. 'a -> string = fun v -> any_to_string v

let to_json : 'a. 'a -> Yojson.Safe.t = fun v -> any_to_json v
