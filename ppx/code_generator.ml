(** Code generator for template expansion *)

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

(** Find converter by naming convention for a type *)
let find_convention_converter ~loc scope (ty : core_type) =
  match Scope_analyzer.converter_name_for_type ty with
  | Some converter_name when Scope_analyzer.has_binding scope converter_name ->
      Some (evar ~loc converter_name)
  | _ -> None
;;

(** Find stringifier by naming convention for a type *)
let find_convention_stringifier ~loc scope (ty : core_type) =
  match Scope_analyzer.stringifier_name_for_type ty with
  | Some stringifier_name when Scope_analyzer.has_binding scope stringifier_name
    -> Some (evar ~loc stringifier_name)
  | _ -> None
;;

(** Extract type name for error messages *)
let type_name_for_error (ty : core_type) : string =
  match Scope_analyzer.extract_type_name ty with
  | Some name -> name
  | None -> "<complex type>"
;;

(** Emit a helpful error message when type cannot be converted *)
let emit_type_error ~loc var_name (ty : core_type option) =
  match ty with
  | Some t ->
      let type_name = type_name_for_error t in
      let converter_name = type_name ^ "_to_json" in
      Location.raise_errorf ~loc
        "MessageTemplates: No JSON converter found for variable '%s' of type '%s'.\n\nOptions:\n1. Define a converter: let %s (x : %s) = `Assoc [...]\n2. Add type annotation with a primitive: (%s : string)\n3. Use [@@deriving converter] on the type definition"
        var_name type_name converter_name type_name var_name
  | None ->
      Location.raise_errorf ~loc
        "MessageTemplates: Cannot determine type for template variable '%s'.\n\nAdd an explicit type annotation: (%s : string)"
        var_name var_name
;;

(** Convert a value to its Yojson representation based on type *)
let rec yojson_of_value ~loc scope (expr : expression) (ty : core_type option) =
  match ty with
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "string"; _}, []); _} ->
      [%expr `String [%e expr]]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "int"; _}, []); _} ->
      [%expr `Int [%e expr]]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "float"; _}, []); _} ->
      [%expr `Float [%e expr]]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "bool"; _}, []); _} ->
      [%expr `Bool [%e expr]]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "int64"; _}, []); _} ->
      [%expr `Intlit (Int64.to_string [%e expr])]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "int32"; _}, []); _} ->
      [%expr `Intlit (Int32.to_string [%e expr])]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "nativeint"; _}, []); _} ->
      [%expr `Intlit (Nativeint.to_string [%e expr])]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "char"; _}, []); _} ->
      [%expr `String (String.make 1 [%e expr])]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "unit"; _}, []); _} ->
      [%expr `Null]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "list"; _}, [elem_ty]); _} ->
      (* For lists, we handle the element type recursively *)
      let x_var = evar ~loc "x" in
      let elem_converter = yojson_of_value ~loc scope x_var (Some elem_ty) in
      [%expr `List (List.map (fun x -> [%e elem_converter]) [%e expr])]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "array"; _}, [elem_ty]); _} ->
      let x_var = evar ~loc "x" in
      let elem_converter = yojson_of_value ~loc scope x_var (Some elem_ty) in
      [%expr
        `List
          (Array.to_list (Array.map (fun x -> [%e elem_converter]) [%e expr]))]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "option"; _}, [elem_ty]); _} ->
      let x_var = evar ~loc "x" in
      let elem_converter = yojson_of_value ~loc scope x_var (Some elem_ty) in
      [%expr
        match [%e expr] with
        | None -> `Null
        | Some x -> [%e elem_converter]]
  | Some ty -> (
    (* Try convention-based converter for unknown types *)
    match find_convention_converter ~loc scope ty with
    | Some converter -> [%expr [%e converter] [%e expr]]
    | None ->
        (* Type is known but no converter found *)
        let type_name = type_name_for_error ty in
        let converter_name = type_name ^ "_to_json" in
        Location.raise_errorf ~loc
          "MessageTemplates: No JSON converter found for type '%s'.\n\nDefine a converter: let %s x = `Assoc [...]\nOr use a primitive type with explicit annotation: (x : string)"
          type_name converter_name )
  | None ->
      (* No type information available *)
      Location.raise_errorf ~loc
        "MessageTemplates: Cannot determine type for template variable.\n\nAdd an explicit type annotation: (var : string)\nOr define a converter: let var_to_json x = `String x"
;;

(** Apply operator-specific transformations *)
let apply_operator ~loc scope op expr ty =
  match op with
  | Default -> yojson_of_value ~loc scope expr ty
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
      let json_expr = yojson_of_value ~loc scope expr ty in
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
let rec build_string_render ~loc scope parts =
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
          (* For stringify, use yojson_of_value then to_string *)
          let ty = Scope_analyzer.find_variable scope h.name in
          let var_expr = evar ~loc h.name in
          let json_expr = yojson_of_value ~loc scope var_expr ty in
          [%expr Yojson.Safe.to_string [%e json_expr]]
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
    | _ -> build_buffer_render ~loc scope parts
  else if has_formats then
    build_printf_render ~loc scope parts
  else if hole_count > 2 || List.length parts > 4 then
    build_buffer_render ~loc scope parts
  else
    build_printf_render ~loc scope parts

(** Build string render using Buffer for complex templates *)
and build_buffer_render ~loc scope parts =
  let buf_var = evar ~loc "__buf" in

  let add_calls =
    List.map
      (function
        | Text s -> [%expr Buffer.add_string [%e buf_var] [%e estring ~loc s]]
        | Hole h ->
            let var = evar ~loc h.name in
            let ty = Scope_analyzer.find_variable scope h.name in
            let json_expr = yojson_of_value ~loc scope var ty in
            [%expr
              Buffer.add_string [%e buf_var]
                (Yojson.Safe.to_string [%e json_expr])] )
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
and build_printf_render ~loc scope parts =
  let fmt_string = build_format_string parts in
  let var_exprs =
    List.filter_map
      (function
        | Text _ -> None
        | Hole h ->
            let var = evar ~loc h.name in
            let ty = Scope_analyzer.find_variable scope h.name in
            let expr =
              match h.operator with
              | Stringify ->
                  let json_expr = yojson_of_value ~loc scope var ty in
                  [%expr Yojson.Safe.to_string [%e json_expr]]
              | _ -> var
            in
            Some expr )
      parts
  in
  eapply ~loc (evar ~loc "Printf.sprintf") (estring ~loc fmt_string :: var_exprs)
;;

(** Generate code for a template *)
let generate_template_code ~loc scope parts =
  let string_render = build_string_render ~loc scope parts in

  (* Build JSON properties *)
  let properties =
    List.filter_map
      (function
        | Text _ -> None
        | Hole h ->
            let ty = Scope_analyzer.find_variable scope h.name in
            let value_expr =
              apply_operator ~loc scope h.operator (evar ~loc h.name) ty
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
    [%expr
      `String
        [%e estring ~loc (Message_templates.Types.reconstruct_template parts)]]
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
