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

(** Calculate edit distance between two strings (Levenshtein distance) *)
let edit_distance s1 s2 =
  let len1 = String.length s1 in
  let len2 = String.length s2 in
  if len1 = 0 then
    len2
  else if len2 = 0 then
    len1
  else
    let matrix = Array.make_matrix (len1 + 1) (len2 + 1) 0 in
    for i = 0 to len1 do
      matrix.(i).(0) <- i
    done;
    for j = 0 to len2 do
      matrix.(0).(j) <- j
    done;
    for i = 1 to len1 do
      for j = 1 to len2 do
        let cost =
          if s1.[i - 1] = s2.[j - 1] then
            0
          else
            1
        in
        matrix.(i).(j) <-
          min
            (min (matrix.(i - 1).(j) + 1) (matrix.(i).(j - 1) + 1))
            (matrix.(i - 1).(j - 1) + cost)
      done
    done;
    matrix.(len1).(len2)
;;

(** Get all variable names in scope *)
let rec get_all_variables scope =
  let current = List.map fst scope.bindings in
  match scope.outer_scopes with
  | [] -> current
  | outer :: _ -> current @ get_all_variables outer
;;

(** Find similar variable names (suggestions) *)
let find_suggestions var_name available =
  let scored =
    List.map (fun name -> (name, edit_distance var_name name)) available
  in
  let sorted = List.sort (fun (_, d1) (_, d2) -> compare d1 d2) scored in
  List.filter (fun (_, d) -> d <= 3) sorted
  |> List.map fst
  |> List.filter (fun n -> n <> var_name)
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
