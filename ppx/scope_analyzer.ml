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

(** Extract variable names from a pattern *)
let rec extract_pattern_names pat =
  match pat.ppat_desc with
  | Ppat_var {txt= name; _} -> [name]
  | Ppat_tuple pats -> List.concat_map extract_pattern_names pats
  | Ppat_record (fields, _) ->
      List.map (fun (_, pat) -> extract_pattern_names pat) fields |> List.concat
  | Ppat_alias (pat, {txt= name; _}) -> name :: extract_pattern_names pat
  | _ -> []
;;

(** Build scope from let bindings *)
let scope_from_let_bindings vbs =
  List.fold_left
    (fun scope vb ->
      let names = extract_pattern_names vb.pvb_pat in
      (* Type information not available at PPX stage, so we store None *)
      List.fold_left (fun sc name -> add_binding name None sc) scope names )
    empty_scope vbs
;;

(** Build scope from function parameters *)
let scope_from_params pat =
  let names = extract_pattern_names pat in
  List.fold_left
    (fun scope name -> add_binding name None scope)
    empty_scope names
;;
