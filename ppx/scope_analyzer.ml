(** Scope analysis for variable validation in templates *)

open Ppxlib

(** Type representing the scope context *)
type scope =
  { bindings: (string * core_type option) list
  ; outer_scopes: scope list }

(** Create an empty scope *)
let empty_scope = {bindings= []; outer_scopes= []}

(** Add a binding to the current scope *)
let add_binding name ty scope =
  {scope with bindings= (name, ty) :: scope.bindings}
;;

(** Push a new scope level *)
let push_scope scope = {bindings= []; outer_scopes= scope :: scope.outer_scopes}

(** Check if a variable exists in scope chain *)
let rec find_variable scope var_name =
  match List.assoc_opt var_name scope.bindings with
  | Some ty_opt -> ty_opt
  | None -> (
    match scope.outer_scopes with
    | [] -> None
    | outer :: _ -> find_variable outer var_name )
;;

(** Check if a converter exists in scope based on naming convention *)
let rec has_binding scope name =
  match List.assoc_opt name scope.bindings with
  | Some _ -> true
  | None -> (
    match scope.outer_scopes with
    | [] -> false
    | outer :: _ -> has_binding outer name )
;;

(** Get all variable names in scope *)
let rec get_all_variables scope =
  let current = List.map fst scope.bindings in
  match scope.outer_scopes with
  | [] -> current
  | outer :: _ -> current @ get_all_variables outer
;;

(** Simple suggestion function: find variables that share a prefix *)
let find_suggestions var_name available =
  let prefix_len = min 2 (String.length var_name) in
  if prefix_len = 0 then
    []
  else
    let prefix = String.sub var_name 0 prefix_len in
    available
    |> List.filter (fun name ->
        name <> var_name && String.starts_with ~prefix name )
    |> List.sort String.compare
    |> fun lst -> List.take (min 3 (List.length lst)) lst
;;

(** Format variable list for error message *)
let format_variables vars =
  match vars with
  | [] -> "  (none)"
  | _ ->
      vars
      |> List.sort String.compare
      |> List.map (fun v -> Printf.sprintf "  - %s" v)
      |> String.concat "\n"
;;

(** Validate that a variable exists in scope, raising a compile error if not *)
let validate_variable ~loc scope var_name =
  match find_variable scope var_name with
  | None ->
      let available = get_all_variables scope in
      let suggestions = find_suggestions var_name available in
      let suggestion_msg =
        match suggestions with
        | [] -> ""
        | [s] -> Printf.sprintf "\n\nDid you mean: '%s'?" s
        | ss ->
            "\n\nDid you mean one of these?\n"
            ^ String.concat "\n"
                (List.map (fun s -> Printf.sprintf "  - '%s'" s) ss)
      in
      Location.raise_errorf ~loc
        "Variable '%s' not found in scope.\n\nAvailable variables:\n%s%s"
        var_name
        (format_variables available)
        suggestion_msg
  | ty -> ty
;;

(** Infer type from a literal expression *)
let type_of_literal_expr expr =
  let make_type desc =
    { ptyp_desc= desc
    ; ptyp_loc= expr.pexp_loc
    ; ptyp_attributes= []
    ; ptyp_loc_stack= [] }
  in
  let make_type_var () =
    { ptyp_desc= Ptyp_var "_"
    ; ptyp_loc= expr.pexp_loc
    ; ptyp_attributes= []
    ; ptyp_loc_stack= [] }
  in
  match expr.pexp_desc with
  | Pexp_constant (Pconst_string _) ->
      Some
        (make_type
           (Ptyp_constr ({txt= Lident "string"; loc= expr.pexp_loc}, [])) )
  | Pexp_constant (Pconst_integer _) ->
      Some
        (make_type (Ptyp_constr ({txt= Lident "int"; loc= expr.pexp_loc}, [])))
  | Pexp_constant (Pconst_float _) ->
      Some
        (make_type
           (Ptyp_constr ({txt= Lident "float"; loc= expr.pexp_loc}, [])) )
  | Pexp_construct ({txt= Lident "true" | Lident "false"; _}, None) ->
      Some
        (make_type (Ptyp_constr ({txt= Lident "bool"; loc= expr.pexp_loc}, [])))
  | Pexp_construct ({txt= Lident "()"; _}, None) ->
      Some
        (make_type (Ptyp_constr ({txt= Lident "unit"; loc= expr.pexp_loc}, [])))
  | Pexp_construct ({txt= Lident "[]"; _}, None) ->
      (* Empty list - element type is unknown, but we know it's a list *)
      Some
        (make_type
           (Ptyp_constr
              ({txt= Lident "list"; loc= expr.pexp_loc}, [make_type_var ()]) ) )
  | _ -> None
;;

(** Extract variable names and their types from a pattern *)
let rec extract_pattern_names_with_types pat =
  match pat.ppat_desc with
  | Ppat_var {txt= name; _} ->
      (* Check if there's a type annotation on the pattern *)
      let ty_opt =
        match pat.ppat_attributes with
        | [ { attr_name= {txt= "ocaml.typ"; _}
            ; attr_payload= PStr [{pstr_desc= Pstr_eval (expr, _); _}]
            ; _ } ] ->
            (* Try to extract type from attribute - this is complex, skip for
               now *)
            None
        | _ -> None
      in
      [(name, ty_opt)]
  | Ppat_constraint (inner_pat, ty) ->
      (* Pattern with type annotation: (x : int) *)
      let names = extract_pattern_names inner_pat in
      List.map (fun name -> (name, Some ty)) names
  | Ppat_tuple pats -> List.concat_map extract_pattern_names_with_types pats
  | Ppat_record (fields, _) ->
      List.concat_map
        (fun (_, pat) -> extract_pattern_names_with_types pat)
        fields
  | Ppat_alias (pat, {txt= name; _}) ->
      let inner = extract_pattern_names_with_types pat in
      (name, None) :: inner
  | _ -> []

(** Extract variable names from a pattern (legacy, type-less) *)
and extract_pattern_names pat =
  List.map fst (extract_pattern_names_with_types pat)
;;

(** Build scope from let bindings with type information *)
let scope_from_let_bindings vbs =
  List.fold_left
    (fun scope vb ->
      (* Check for type constraint on the pattern itself *)
      let pat_types = extract_pattern_names_with_types vb.pvb_pat in
      (* Check for type annotation on the expression: let x : int = 42 *)
      (* Also infer type from literal expressions: let x = "hello" *)
      let expr_type =
        match vb.pvb_expr.pexp_desc with
        | Pexp_constraint (_, ty) -> Some ty
        | Pexp_coerce (_, _, ty) -> Some ty
        | _ ->
            (* Try to infer from literal *)
            type_of_literal_expr vb.pvb_expr
      in
      List.fold_left
        (fun sc (name, pat_ty) ->
          (* Use pattern type if available, otherwise use expression type *)
          let final_ty =
            match pat_ty with
            | Some _ -> pat_ty
            | None -> expr_type
          in
          add_binding name final_ty sc )
        scope pat_types )
    empty_scope vbs
;;

(** Build scope from function parameters with type information *)
let scope_from_params pat =
  let bindings = extract_pattern_names_with_types pat in
  List.fold_left
    (fun scope (name, ty_opt) -> add_binding name ty_opt scope)
    empty_scope bindings
;;

(** Extract type name from a core_type *)
let extract_type_name (ty : core_type) : string option =
  match ty.ptyp_desc with
  | Ptyp_constr ({txt= Lident name; _}, []) -> Some name
  | Ptyp_constr ({txt= Ldot (_, name); _}, []) -> Some name
  | _ -> None
;;

(** Generate convention-based converter name for a type *)
let converter_name_for_type (ty : core_type) : string option =
  extract_type_name ty |> Option.map (fun name -> name ^ "_to_json")
;;

(** Generate convention-based stringifier name for a type *)
let stringifier_name_for_type (ty : core_type) : string option =
  extract_type_name ty |> Option.map (fun name -> name ^ "_to_string")
;;
