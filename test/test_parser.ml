(** Tests for the template parser *)

open Alcotest
open Message_templates

let test_parse_simple () =
  let template = "Hello {name}" in
  match Template_parser.parse_template template with
  | Ok parts ->
      check int "Number of parts" 2 (List.length parts);
      (match parts with
       | [Types.Text "Hello "; Types.Hole h] ->
           check string "Hole name" "name" h.name;
           check bool "Default operator" true (h.operator = Types.Default)
       | _ -> fail "Unexpected parts structure")
  | Error msg -> fail msg

let test_parse_with_operator () =
  let template = "User {@user} made {$count} requests" in
  match Template_parser.parse_template template with
  | Ok parts ->
      let holes = Template_parser.extract_holes parts in
      check int "Number of holes" 2 (List.length holes);
      (match holes with
       | [u; c] ->
           check string "First hole name" "user" u.name;
           check bool "Structure operator" true (u.operator = Types.Structure);
           check string "Second hole name" "count" c.name;
           check bool "Stringify operator" true (c.operator = Types.Stringify)
       | _ -> fail "Unexpected holes")
  | Error msg -> fail msg

let test_parse_escaped_braces () =
  let template = "{{not_a_hole}}" in
  match Template_parser.parse_template template with
  | Ok parts ->
      check int "Number of parts" 3 (List.length parts);
      (match parts with
       | [Types.Text "{"; Types.Text "not_a_hole"; Types.Text "}"] -> ()
       | _ -> fail (Printf.sprintf "Expected escaped braces to produce three text parts, got: %s"
           (String.concat "; " (List.map (function
             | Types.Text s -> Printf.sprintf "Text %S" s
             | Types.Hole h -> Printf.sprintf "Hole %s" h.name) parts))))
  | Error msg -> fail msg

let test_parse_with_format () =
  let template = "ID: {count:00000}" in
  match Template_parser.parse_template template with
  | Ok parts ->
      let holes = Template_parser.extract_holes parts in
      check int "Number of holes" 1 (List.length holes);
      (match holes with
       | [h] ->
           check string "Hole name" "count" h.name;
           check (option string) "Format" (Some "00000") h.format
       | _ -> fail "Unexpected holes")
  | Error msg -> fail msg

let test_parse_empty () =
  let template = "" in
  match Template_parser.parse_template template with
  | Ok parts ->
      check int "Empty template has no parts" 0 (List.length parts)
  | Error msg -> fail msg

let () =
  run "Template Parser Tests" [
    "basic", [
      test_case "Simple template" `Quick test_parse_simple;
      test_case "With operators" `Quick test_parse_with_operator;
      test_case "Escaped braces" `Quick test_parse_escaped_braces;
      test_case "Format specifier" `Quick test_parse_with_format;
      test_case "Empty template" `Quick test_parse_empty;
    ];
  ]
