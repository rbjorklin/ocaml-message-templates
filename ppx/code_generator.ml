(** Code generator for template expansion *)

open Ppxlib
open Ast_builder.Default
open Message_templates.Types

(** Build a format string for Printf from template parts *)
let build_format_string parts =
  let buf = Buffer.create 256 in
  List.iter (function
    | Text s -> 
        (* Escape % characters for Printf *)
        let escaped = String.concat "%%" (String.split_on_char '%' s) in
        Buffer.add_string buf escaped
    | Hole h ->
        match h.format with
        | None -> Buffer.add_string buf "%s"
        | Some fmt -> Buffer.add_string buf ("%" ^ fmt)
  ) parts;
  Buffer.contents buf

(** Convert a value to its Yojson representation based on type *)
let yojson_of_value ~loc (expr : expression) (ty : core_type option) =
  match ty with
  | Some { ptyp_desc = Ptyp_constr ({ txt = Lident "string"; _ }, []); _ } -> 
      [%expr `String [%e expr]]
  | Some { ptyp_desc = Ptyp_constr ({ txt = Lident "int"; _ }, []); _ } -> 
      [%expr `Int [%e expr]]
  | Some { ptyp_desc = Ptyp_constr ({ txt = Lident "float"; _ }, []); _ } -> 
      [%expr `Float [%e expr]]
  | Some { ptyp_desc = Ptyp_constr ({ txt = Lident "bool"; _ }, []); _ } -> 
      [%expr `Bool [%e expr]]
  | Some { ptyp_desc = Ptyp_constr ({ txt = Lident "int64"; _ }, []); _ } -> 
      [%expr `Intlit (Int64.to_string [%e expr])]
  | _ -> 
      (* Fallback: convert to string using runtime helper *)
      [%expr `String (Message_templates.Runtime_helpers.to_string [%e expr])]

(** Apply operator-specific transformations *)
let apply_operator ~loc op expr ty =
  match op with
  | Default -> yojson_of_value ~loc expr ty
  | Structure -> 
      (* Assume value is already Yojson.Safe.t or convert to string *)
      [%expr 
        match [%e expr] with
        | (`Assoc _ | `Bool _ | `Float _ | `Int _ | `Intlit _ | `List _ | `Null | `String _ | `Tuple _) as json -> json
        | v -> `String (Yojson.Safe.to_string v)
      ]
  | Stringify ->
      [%expr `String (Message_templates.Runtime_helpers.to_string [%e expr])]

(** Generate code for a template *)
let generate_template_code ~loc scope parts =
  (* Build format string for Printf *)
  let fmt_string = build_format_string parts in
  
  (* Collect variable expressions for string rendering.
     For Stringify operator ($var), we convert to string.
     For others, variables are used directly with format specifiers. *)
  let var_exprs = List.filter_map (function
    | Text _ -> None
    | Hole h -> 
        let var = evar ~loc h.name in
        let expr = 
          match h.operator with
          | Stringify -> 
              (* Convert to string using runtime helper *)
              [%expr Message_templates.Runtime_helpers.to_string [%e var]]
          | _ -> 
              (* Use directly - format specifiers handle type conversion *)
              var
        in
        Some expr
  ) parts in
  
  (* Build string render expression *)
  let string_render = 
    eapply ~loc (evar ~loc "Printf.sprintf") 
      (estring ~loc fmt_string :: var_exprs)
  in
  
  (* Build JSON properties *)
  let properties = List.filter_map (function
    | Text _ -> None
    | Hole h ->
        let ty = Scope_analyzer.find_variable scope h.name in
        let value_expr = apply_operator ~loc h.operator (evar ~loc h.name) ty in
        Some (h.name, value_expr)
  ) parts in
  
  (* Add timestamp field - generate at runtime *)
  let timestamp_expr = 
    [%expr 
      `String (
        match Ptime.of_float_s (Unix.gettimeofday ()) with
        | Some t -> Ptime.to_rfc3339 t
        | None -> "invalid-time"
      )
    ]
  in
  let timestamp_field = ("@t", timestamp_expr) in
  
  (* Add template field - wrap in `String constructor *)
  let template_expr = [%expr `String [%e estring ~loc (reconstruct_template parts)]] in
  let template_field = ("@m", template_expr) in
  
  (* Build field list: timestamp, template, then properties *)
  let assoc_fields = timestamp_field :: template_field :: properties in
  
  (* Build JSON expression: `Assoc [...] *)
  let json_expr = 
    let fields = List.map (fun (name, expr) ->
      [%expr ([%e estring ~loc name], [%e expr])]
    ) assoc_fields in
    [%expr `Assoc [%e elist ~loc fields]]
  in
  
  (* Return tuple: (string, Yojson.Safe.t) *)
  pexp_tuple ~loc [string_render; json_expr]
