(** PPX rewriter for Message Templates *)

open Ppxlib

let name = "template"

(** Find position of error in template string for better error reporting *)
let find_error_context template_str error_msg =
  (* Common error patterns *)
  if
    (try String.index error_msg 'U' with Not_found -> -1) >= 0
    || (try String.index error_msg 'u' with Not_found -> -1) >= 0
  then
    let pos = try String.index template_str '{' with Not_found -> -1 in
    if pos >= 0 then
      let before = String.sub template_str 0 (min pos 20) in
      let after =
        let start = pos + 1 in
        let len = min 20 (String.length template_str - start) in
        String.sub template_str start len
      in
      let arrow_spaces = String.make (String.length before + 1) ' ' in
      let context =
        "  " ^ before ^ "{ " ^ after ^ "\n  " ^ arrow_spaces ^ "^"
      in
      Some context
    else
      None
  else
    None
;;

(** Create helpful error message for template parse errors *)
let format_parse_error template_str error_msg =
  let context = find_error_context template_str error_msg in
  match context with
  | Some ctx ->
      Printf.sprintf
        "Invalid template syntax\n\nTemplate: \"%s\"\n%s\n\nError: %s"
        template_str ctx error_msg
  | None ->
      Printf.sprintf "Failed to parse template: %s\n\nTemplate: \"%s\""
        error_msg template_str
;;

let expand ~ctxt template_str =
  let loc = Expansion_context.Extension.extension_point_loc ctxt in

  (* Parse the template *)
  let parsed =
    match Message_templates.Template_parser.parse_template template_str with
    | Ok parts -> parts
    | Error msg ->
        Location.raise_errorf ~loc "%s" (format_parse_error template_str msg)
  in

  (* Extract holes from the parsed template *)
  let holes = Message_templates.Template_parser.extract_holes parsed in

  (* Build a scope with all referenced variables. Since we don't have access to
     the surrounding context in a context-free rule, we create bindings for all
     variables referenced in the template. The OCaml compiler will catch
     undefined variables at type-checking time. *)
  let scope =
    List.fold_left
      (fun sc (hole : Message_templates.Types.hole) ->
        Scope_analyzer.add_binding hole.name None sc )
      Scope_analyzer.empty_scope holes
  in

  (* Generate the template code *)
  Code_generator.generate_template_code ~loc scope parsed
;;

let extension =
  Extension.V3.declare name Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    expand
;;

let rule = Ppxlib.Context_free.Rule.extension extension

let () = Driver.register_transformation ~rules:[rule] "message-templates"
