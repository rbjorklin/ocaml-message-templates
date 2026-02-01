(** Runtime helpers for message templates *)

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
