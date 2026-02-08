(** PPX rewriter for level-aware logging *)

open Ppxlib
open Ast_builder.Default

(** Map from log level names to their corresponding functions in Log module *)
let level_functions =
  [ ("verbose", "Log.verbose")
  ; ("debug", "Log.debug")
  ; ("information", "Log.information")
  ; ("warning", "Log.warning")
  ; ("error", "Log.error")
  ; ("fatal", "Log.fatal") ]
;;

(** Extract type name from a core_type *)
let extract_type_name (ty : core_type) : string option =
  match ty.ptyp_desc with
  | Ptyp_constr ({txt= Lident name; _}, []) -> Some name
  | Ptyp_constr ({txt= Ldot (_, name); _}, []) -> Some name
  | _ -> None
;;

(** Generate converter name from type *)
let converter_name_for_type (ty : core_type) : string option =
  extract_type_name ty |> Option.map (fun name -> name ^ "_to_json")
;;

(** Convert a value to its Yojson representation based on type *)
let rec yojson_of_value ~loc (expr : expression) (ty : core_type option) =
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
      let x_var = evar ~loc "x" in
      let elem_converter = yojson_of_value ~loc x_var (Some elem_ty) in
      [%expr `List (List.map (fun x -> [%e elem_converter]) [%e expr])]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "array"; _}, [elem_ty]); _} ->
      let x_var = evar ~loc "x" in
      let elem_converter = yojson_of_value ~loc x_var (Some elem_ty) in
      [%expr
        `List
          (Array.to_list (Array.map (fun x -> [%e elem_converter]) [%e expr]))]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "option"; _}, [elem_ty]); _} ->
      let x_var = evar ~loc "x" in
      let elem_converter = yojson_of_value ~loc x_var (Some elem_ty) in
      [%expr
        match [%e expr] with
        | None -> `Null
        | Some x -> [%e elem_converter]]
  | Some ty -> (
    (* Try convention-based converter *)
    match converter_name_for_type ty with
    | Some converter_name ->
        let converter = evar ~loc converter_name in
        [%expr [%e converter] [%e expr]]
    | None ->
        let type_name =
          match extract_type_name ty with
          | Some n -> n
          | None -> "<complex>"
        in
        Location.raise_errorf ~loc
          "MessageTemplates: No converter found for type '%s'. Define %s_to_json or use a primitive type."
          type_name type_name )
  | None ->
      (* No type information - require explicit annotation *)
      Location.raise_errorf ~loc
        "MessageTemplates: Cannot determine type for template variable. Add explicit type annotation: (var : string)"
;;

(** Generate the PPX expansion for a log level extension *)
let expand_log_level level_name ~ctxt template_str =
  let loc = Expansion_context.Extension.extension_point_loc ctxt in

  (* Parse the template *)
  let parsed =
    match Message_templates.Template_parser.parse_template template_str with
    | Ok parts -> parts
    | Error msg ->
        Location.raise_errorf ~loc "MessageTemplates: Parse error: %s" msg
  in

  (* Extract holes from the parsed template *)
  let holes = Message_templates.Template_parser.extract_holes parsed in

  (* Build the message string (the template itself) *)
  let message_expr = Ast_builder.Default.estring ~loc template_str in

  (* Build the properties list from holes *)
  let properties =
    List.map
      (fun (hole : Message_templates.Types.hole) ->
        let name = hole.name in
        (* For log levels, we need type information from scope. Since we don't
           have full scope analysis here, require the user to provide explicit
           properties with converters. *)
        let converter_expr =
          Location.raise_errorf ~loc
            "MessageTemplates: Variable '%s' in log template requires explicit type information.\n\nUse the Log module directly with explicit properties:\nLog.%s \"%s\" [(\"%s\", your_type_to_json %s)]\n\nOr use [%%template \"%s\"] with a let-binding that has a type annotation."
            name level_name template_str name name template_str
        in

        (* Create a tuple (name, value) *)
        Ast_builder.Default.pexp_tuple ~loc
          [Ast_builder.Default.estring ~loc name; converter_expr] )
      holes
  in

  (* Create the properties list expression *)
  let properties_expr = Ast_builder.Default.elist ~loc properties in

  (* Get the Log function name *)
  let log_function =
    match List.assoc_opt level_name level_functions with
    | Some fn -> fn
    | None -> Location.raise_errorf ~loc "Unknown log level: %s" level_name
  in

  (* Create the function expression *)
  let lid = Longident.parse log_function in
  let fn_expr = Ast_builder.Default.pexp_ident ~loc {txt= lid; loc} in

  (* Build the final expression: Log.level "message" [properties] *)
  Ast_builder.Default.eapply ~loc fn_expr [message_expr; properties_expr]
;;

(** Create extensions for all log levels *)
let create_level_extension level_name =
  let name = "log." ^ level_name in
  Extension.V3.declare name Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    (expand_log_level level_name)
;;

(** Register all log level extensions *)
let () =
  let extensions =
    List.map
      (fun (level, _) ->
        let ext = create_level_extension level in
        Ppxlib.Context_free.Rule.extension ext )
      level_functions
  in

  Driver.register_transformation ~rules:extensions
    "message-templates-log-levels"
;;
