(** PPX rewriter for level-aware logging *)

open Ppxlib

(** Map from log level names to their corresponding functions in Log module *)
let level_functions =
  [ ("verbose", "Log.verbose")
  ; ("debug", "Log.debug")
  ; ("information", "Log.information")
  ; ("warning", "Log.warning")
  ; ("error", "Log.error")
  ; ("fatal", "Log.fatal") ]
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
        let var_expr = Ast_builder.Default.evar ~loc name in

        (* Create a tuple (name, value) - preserve types using to_json *)
        Ast_builder.Default.pexp_tuple ~loc
          [ Ast_builder.Default.estring ~loc name
          ; [%expr
              Message_templates.Runtime_helpers.generic_to_json [%e var_expr]]
          ] )
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
