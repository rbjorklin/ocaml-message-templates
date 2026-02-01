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

(** Validate that a variable exists in scope, raising a compile error if not *)
let validate_variable ~loc scope var_name =
  match find_variable scope var_name with
  | None ->
      Location.raise_errorf ~loc
        "MessageTemplates: Variable '%s' not found in scope. Ensure the variable is defined before using it in a template."
        var_name
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
