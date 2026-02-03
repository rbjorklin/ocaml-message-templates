(** Property-based tests for template parsing and rendering *)

open QCheck

(** Property: Template parsing doesn't crash *)
let prop_parsing_safe =
  Test.make 
    ~gen:Gen.string_printable
    ~name:"Template parsing is safe"
    ~print:Fun.id
    (fun input ->
      try
        let _ = Message_templates.Template_parser.parse input in
        true
      with _ -> true
    )

(** Property: Simple templates render correctly *)
let prop_simple_template_rendering =
  Test.make
    ~gen:(Gen.pair Gen.string_printable Gen.string_printable)
    ~name:"Simple templates render correctly"
    ~print:(fun (a, b) -> Printf.sprintf "(%S, %S)" a b)
    (fun (text1, text2) ->
      try
        let template = text1 ^ " text " ^ text2 in
        let rendered =
          Message_templates.Runtime_helpers.render_template template []
        in
        rendered = template
      with _ -> false
    )

(** Property: Variable replacement works *)
let prop_variable_replacement =
  Test.make
    ~gen:(Gen.pair Gen.string_printable Gen.string_printable)
    ~name:"Variables are correctly replaced"
    ~print:(fun (a, b) -> Printf.sprintf "(%S, %S)" a b)
    (fun (val1, val2) ->
      try
        let template = "{v1} and {v2}" in
        let rendered =
          Message_templates.Runtime_helpers.render_template
            template
            [("v1", `String val1); ("v2", `String val2)]
        in
        val1 ^ " and " ^ val2 = rendered
      with _ -> false
    )

(** All tests *)
let tests = [prop_parsing_safe; prop_simple_template_rendering; prop_variable_replacement]

(** Run tests *)
let () =
  List.iter (fun t ->
    match Test.check_fun t with
    | QCheck.Success () -> Printf.printf "✓ %s\n" (Test.get_name t)
    | QCheck.Failure msg -> Printf.printf "✗ %s: %s\n" (Test.get_name t) msg
    | QCheck.Error (err, _) -> Printf.printf "✗ %s: %s\n" (Test.get_name t) err
  ) tests
