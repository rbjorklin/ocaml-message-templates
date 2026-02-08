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

module Safe_conversions = struct
  type 'a t = 'a -> Yojson.Safe.t

  let make : 'a. ('a -> Yojson.Safe.t) -> 'a t = fun f -> f

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

(** Generic value to string conversion using Obj module. *)
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
  (* Try to traverse a Set/Map tree structure and return elements as a list
     Returns None if it doesn't look like a Set/Map tree Set: Node of {l; v; r;
     h} -> 4 fields (left, value, right, height) Map: Node of {l; v; d; r; h} ->
     5 fields (left, key, data, right, height) *)
  and try_traverse_set_tree repr =
    let size = O.size repr in
    let tag = O.tag repr in
    (* Check if this looks like a Set Node (4 fields) or Map Node (5 fields) *)
    if tag = 0 && (size = 4 || size = 5) then
      try
        let left = O.field repr 0 in
        let key = O.field repr 1 in
        let right = O.field repr (size - 2) in
        let _height = O.field repr (size - 1) in
        (* Verify height field is an integer (sanity check) *)
        if not (O.is_int _height) then
          raise Exit;
        (* For Map, the value is at index 2; for Set, the value is at index 1 *)
        let value_str =
          if size = 5 then
            (* Map - show as (key, value) pair *)
            let value = O.field repr 2 in
            "("
            ^ generic_to_string_impl key
            ^ ", "
            ^ generic_to_string_impl value
            ^ ")"
          else
            (* Set - just show the value *)
            generic_to_string_impl key
        in
        (* Recursively collect elements *)
        let left_elements =
          if O.is_int left then
            (* Empty *)
            []
          else
            match
              try_traverse_set_tree left
            with
            | Some els -> els
            | None -> raise Exit
        in
        let right_elements =
          if O.is_int right then
            (* Empty *)
            []
          else
            match
              try_traverse_set_tree right
            with
            | Some els -> els
            | None -> raise Exit
        in
        Some (left_elements @ [value_str] @ right_elements)
      with Exit -> None
    else
      None
  and block_to_string repr =
    (* Convert a block to string by showing its fields *)
    let size = O.size repr in
    let tag = O.tag repr in
    (* First, try to detect and format as Set/Map (4 or 5 fields with tag 0) *)
    if (size = 4 || size = 5) && tag = 0 then
      match
        try_traverse_set_tree repr
      with
      | Some elements -> "[" ^ String.concat "; " elements ^ "]"
      | None ->
          let fields =
            List.init size (fun i -> generic_to_string_impl (O.field repr i))
          in
          "(" ^ String.concat ", " fields ^ ")"
    else if size = 0 then
      "()"
    else
      let fields =
        List.init size (fun i -> generic_to_string_impl (O.field repr i))
      in
      "(" ^ String.concat ", " fields ^ ")"
  and generic_to_string_impl repr =
    if O.is_int repr then
      string_of_int (O.obj repr)
    else if O.is_block repr then
      match
        O.tag repr
      with
      | 252 -> (O.obj repr : string)
      | 253 -> string_of_float (O.obj repr : float)
      | 254 ->
          (* Flat float array - convert to list representation *)
          let size = O.size repr in
          let floats =
            List.init size (fun i -> string_of_float (O.double_field repr i))
          in
          "[" ^ String.concat "; " floats ^ "]"
      | 255 -> "<custom>"
      | 251 -> "<abstract>"
      | 250 ->
          (* Forward value - lazy value that has been forced *)
          (* The first field points to the forced value *)
          if O.size repr > 0 then
            generic_to_string_impl (O.field repr 0)
          else
            "<forward>"
      | 249 -> "<infix>"
      | 248 -> "<object>"
      | 247 -> "<closure>"
      | 246 ->
          (* Lazy value - not yet forced *)
          (* Lazy values have a header and thunk function *)
          "<lazy>"
      | 0 ->
          (* Could be a list or a tuple - check if it looks like a cons cell *)
          if O.size repr = 2 then
            (* Might be a list cons cell, try to convert as list *)
            list_to_string (O.obj repr)
          else
            block_to_string repr
      | tag -> block_to_string repr
    else
      "<unknown>"
  in
  generic_to_string_impl (O.repr v)
;;

(** Generic value to JSON conversion. *)
let generic_to_json (type a) (v : a) : Yojson.Safe.t =
  let module O = Obj in
  (* Recursive helper to avoid type annotation issues *)
  let rec convert repr =
    if O.is_int repr then
      `Int (O.obj repr)
    else if O.is_block repr then
      match
        O.tag repr
      with
      | 252 -> `String (O.obj repr : string)
      | 253 -> `Float (O.obj repr : float)
      | 254 ->
          (* Flat float array *)
          let size = O.size repr in
          let floats =
            List.init size (fun i -> `Float (O.double_field repr i))
          in
          `List floats
      | 255 -> `String "<custom>"
      | 251 -> `String "<abstract>"
      | 250 ->
          (* Forward value - dereference to the forced value *)
          if O.size repr > 0 then
            convert (O.field repr 0)
          else
            `String "<forward>"
      | 249 -> `String "<infix>"
      | 248 -> `String "<object>"
      | 247 -> `String "<closure>"
      | 246 -> `String "<lazy>"
      | _ -> `String (generic_to_string v)
    else
      `String "<unknown>"
  in
  convert (O.repr v)
;;

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
