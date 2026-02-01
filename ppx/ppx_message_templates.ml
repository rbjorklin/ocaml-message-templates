(** PPX rewriter for Message Templates *)

open Ppxlib

let name = "template"

let expand ~ctxt template_str =
  let loc = Expansion_context.Extension.extension_point_loc ctxt in
  
  (* Parse the template *)
  let parsed = match Message_templates.Template_parser.parse_template template_str with
    | Ok parts -> parts
    | Error msg -> Location.raise_errorf ~loc "MessageTemplates: Parse error: %s" msg
  in
  
  (* Extract holes from the parsed template *)
  let holes = Message_templates.Template_parser.extract_holes parsed in
  
  (* Build a scope with all referenced variables.
     Since we don't have access to the surrounding context in a context-free rule,
     we create bindings for all variables referenced in the template.
     The OCaml compiler will catch undefined variables at type-checking time. *)
  let scope = 
    List.fold_left (fun sc (hole : Message_templates.Types.hole) ->
      Scope_analyzer.add_binding hole.name None sc
    ) Scope_analyzer.empty_scope holes
  in
  
  (* Generate the template code *)
  Code_generator.generate_template_code ~loc scope parsed

let extension =
  Extension.V3.declare
    name
    Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    expand

let rule = Ppxlib.Context_free.Rule.extension extension
let () = Driver.register_transformation ~rules:[rule] "message-templates"
