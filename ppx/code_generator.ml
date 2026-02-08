(** Code generator for template expansion

    Note: This module uses runtime type conversion via
    Runtime_helpers.generic_to_json because PPX expansion occurs before type
    checking. Type-specific conversions cannot be performed at compile time. See
    scope_analyzer.ml for details. *)

open Ppxlib
open Ast_builder.Default
open Message_templates.Types

(** Build a format string for Printf from template parts *)
let build_format_string parts =
  let buf = Buffer.create 256 in
  List.iter
    (function
      | Text s ->
          (* Escape % characters for Printf *)
          let escaped = String.concat "%%" (String.split_on_char '%' s) in
          Buffer.add_string buf escaped
      | Hole h -> (
        match h.format with
        | None -> Buffer.add_string buf "%s"
        | Some fmt -> Buffer.add_string buf ("%" ^ fmt) ) )
    parts;
  Buffer.contents buf
;;

(** Convert a value to its Yojson representation.

    Type information is not available at PPX expansion time (PPX runs before the
    type checker), so we always use the generic runtime conversion. The type
    parameter is kept for API compatibility but is ignored. *)
let yojson_of_value ~loc (expr : expression) (_ty : core_type option) =
  [%expr Message_templates.Runtime_helpers.generic_to_json [%e expr]]
;;

(** Apply operator-specific transformations.

    Note: The type parameter is not used since type information is not available
    at PPX expansion time. It is kept for API compatibility. *)
let apply_operator ~loc op expr _ty =
  match op with
  | Default -> yojson_of_value ~loc expr None
  | Structure ->
      (* Assume value is already Yojson.Safe.t or convert to string *)
      [%expr
        match [%e expr] with
        | ( `Assoc _
          | `Bool _
          | `Float _
          | `Int _
          | `Intlit _
          | `List _
          | `Null
          | `String _
          | `Tuple _ ) as json -> json
        | v -> `String (Yojson.Safe.to_string v)]
  | Stringify ->
      (* For stringify operator, convert to JSON first then to string *)
      let json_expr = yojson_of_value ~loc expr None in
      [%expr `String (Yojson.Safe.to_string [%e json_expr])]
;;

(** Check if template has format specifiers *)
let has_format_specifiers parts =
  List.exists
    (function
      | Hole h -> h.format <> None
      | _ -> false )
    parts
;;

(** Count holes in template *)
let count_holes parts =
  List.fold_left
    (fun count part ->
      match part with
      | Hole _ -> count + 1
      | _ -> count )
    0 parts
;;

(** Build string render expression. *)
let rec build_string_render ~loc parts scope =
  let hole_count = count_holes parts in
  let has_formats = has_format_specifiers parts in

  if hole_count = 0 then
    match
      parts
    with
    | [Text s] -> estring ~loc s
    | _ ->
        let s =
          String.concat ""
            (List.map
               (function
                 | Text t -> t
                 | Hole _ -> "" )
               parts )
        in
        estring ~loc s
  else if hole_count = 1 && not has_formats then
    let get_hole_expr h =
      match h.operator with
      | Stringify ->
          [%expr
            Message_templates.Runtime_helpers.generic_to_string
              [%e evar ~loc h.name]]
      | _ -> evar ~loc h.name
    in
    match parts with
    | [Text t1; Hole h; Text t2] when t2 = "" ->
        [%expr [%e estring ~loc t1] ^ [%e get_hole_expr h]]
    | [Hole h; Text t2] when t2 = "" -> get_hole_expr h
    | [Hole h] -> get_hole_expr h
    | [Text t1; Hole h] -> [%expr [%e estring ~loc t1] ^ [%e get_hole_expr h]]
    | [Hole h; Text t2] -> [%expr [%e get_hole_expr h] ^ [%e estring ~loc t2]]
    | [Text t1; Hole h; Text t2] ->
        [%expr
          [%e estring ~loc t1] ^ [%e get_hole_expr h] ^ [%e estring ~loc t2]]
    | _ -> build_buffer_render ~loc parts scope
  else if has_formats then
    build_printf_render ~loc parts scope
  else if hole_count > 2 || List.length parts > 4 then
    build_buffer_render ~loc parts scope
  else
    build_printf_render ~loc parts scope

(** Build string render using Buffer for complex templates *)
and build_buffer_render ~loc parts _scope =
  let buf_var = evar ~loc "__buf" in

  let add_calls =
    List.map
      (function
        | Text s -> [%expr Buffer.add_string [%e buf_var] [%e estring ~loc s]]
        | Hole h ->
            let var = evar ~loc h.name in
            [%expr
              Buffer.add_string [%e buf_var]
                (Message_templates.Runtime_helpers.generic_to_string [%e var])] )
      parts
  in

  (* Build the final expression with all buffer operations sequenced *)
  let body =
    List.fold_right
      (fun call acc ->
        [%expr
          let () = [%e call] in
          [%e acc]] )
      add_calls [%expr Buffer.contents __buf]
  in
  [%expr
    let __buf = Buffer.create 256 in
    [%e body]]

(** Build string render using Printf.sprintf *)
and build_printf_render ~loc parts _scope =
  let fmt_string = build_format_string parts in
  let var_exprs =
    List.filter_map
      (function
        | Text _ -> None
        | Hole h ->
            let var = evar ~loc h.name in
            let expr =
              match h.operator with
              | Stringify ->
                  [%expr
                    Message_templates.Runtime_helpers.generic_to_string [%e var]]
              | _ -> var
            in
            Some expr )
      parts
  in
  eapply ~loc (evar ~loc "Printf.sprintf") (estring ~loc fmt_string :: var_exprs)
;;

(** Generate code for a template *)
let generate_template_code ~loc scope parts =
  let string_render = build_string_render ~loc parts scope in

  (* Build JSON properties *)
  let properties =
    List.filter_map
      (function
        | Text _ -> None
        | Hole h ->
            let ty = Scope_analyzer.find_variable scope h.name in
            let value_expr =
              apply_operator ~loc h.operator (evar ~loc h.name) ty
            in
            Some (h.name, value_expr) )
      parts
  in

  let timestamp_expr =
    [%expr
      `String
        (Message_templates.Runtime_helpers.get_current_timestamp_rfc3339 ())]
  in
  let timestamp_field = ("@t", timestamp_expr) in

  (* Add template field - wrap in `String constructor *)
  let template_expr =
    [%expr `String [%e estring ~loc (reconstruct_template parts)]]
  in
  let template_field = ("@m", template_expr) in

  (* Build field list: timestamp, template, then properties *)
  let assoc_fields = timestamp_field :: template_field :: properties in

  (* Build JSON expression: `Assoc [...] *)
  let json_expr =
    let fields =
      List.map
        (fun (name, expr) -> [%expr [%e estring ~loc name], [%e expr]])
        assoc_fields
    in
    [%expr `Assoc [%e elist ~loc fields]]
  in

  (* Return tuple: (string, Yojson.Safe.t) *)
  pexp_tuple ~loc [string_render; json_expr]
;;
