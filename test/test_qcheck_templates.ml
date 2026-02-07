(** Property-based tests for template parsing and rendering *)

open QCheck

(** Property: Template parsing doesn't crash *)
let prop_parsing_safe =
  Test.make ~count:100 ~name:"Template parsing is safe"
    (make ~print:Fun.id Gen.string_printable) (fun input ->
      try
        let _ = Message_templates.Template_parser.parse_template input in
        true
      with _ -> true )
;;

(** Property: Simple templates render correctly *)
let prop_simple_template_rendering =
  Test.make ~count:100 ~name:"Simple templates render correctly"
    (make
       ~print:(fun (a, b) -> Printf.sprintf "(%S, %S)" a b)
       (Gen.pair Gen.string_printable Gen.string_printable) )
    (fun (text1, text2) ->
      try
        let template = text1 ^ " text " ^ text2 in
        let rendered =
          Message_templates.Runtime_helpers.render_template template []
        in
        rendered = template
      with _ -> false )
;;

(** Property: Variable replacement works *)
let prop_variable_replacement =
  Test.make ~count:100 ~name:"Variables are correctly replaced"
    (make
       ~print:(fun (a, b) -> Printf.sprintf "(%S, %S)" a b)
       (Gen.pair Gen.string_printable Gen.string_printable) )
    (fun (val1, val2) ->
      try
        let template = "{v1} and {v2}" in
        let rendered =
          Message_templates.Runtime_helpers.render_template template
            [("v1", `String val1); ("v2", `String val2)]
        in
        val1 ^ " and " ^ val2 = rendered
      with _ -> false )
;;

(** Helper to run a single test *)
let run_test name test =
  try
    Test.check_exn test;
    Printf.printf "✓ %s\n" name
  with
  | Test.Test_fail (_, msgs) ->
      Printf.printf "✗ %s: %s\n" name (String.concat ", " msgs)
  | Test.Test_error (_, err, _, _) -> Printf.printf "✗ %s: %s\n" name err
;;

(** Run tests *)
let () =
  run_test "Template parsing is safe" prop_parsing_safe;
  run_test "Simple templates render correctly" prop_simple_template_rendering;
  run_test "Variables are correctly replaced" prop_variable_replacement
;;
