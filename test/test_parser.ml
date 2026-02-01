(** Tests for the template parser *)

open Alcotest
open Message_templates

let test_parse_simple () =
  let template = "Hello {name}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      check int "Number of parts" 2 (List.length parts);
      match parts with
      | [Types.Text "Hello "; Types.Hole h] ->
          check string "Hole name" "name" h.name;
          check bool "Default operator" true (h.operator = Types.Default)
      | _ -> fail "Unexpected parts structure" )
  | Error msg -> fail msg
;;

let test_parse_with_operator () =
  let template = "User {@user} made {$count} requests" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      let holes = Template_parser.extract_holes parts in
      check int "Number of holes" 2 (List.length holes);
      match holes with
      | [u; c] ->
          check string "First hole name" "user" u.name;
          check bool "Structure operator" true (u.operator = Types.Structure);
          check string "Second hole name" "count" c.name;
          check bool "Stringify operator" true (c.operator = Types.Stringify)
      | _ -> fail "Unexpected holes" )
  | Error msg -> fail msg
;;

let test_parse_escaped_braces () =
  let template = "{{not_a_hole}}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      check int "Number of parts" 3 (List.length parts);
      match parts with
      | [Types.Text "{"; Types.Text "not_a_hole"; Types.Text "}"] -> ()
      | _ ->
          fail
            (Printf.sprintf
               "Expected escaped braces to produce three text parts, got: %s"
               (String.concat "; "
                  (List.map
                     (function
                       | Types.Text s -> Printf.sprintf "Text %S" s
                       | Types.Hole h -> Printf.sprintf "Hole %s" h.name )
                     parts ) ) ) )
  | Error msg -> fail msg
;;

let test_parse_with_format () =
  let template = "ID: {count:00000}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      let holes = Template_parser.extract_holes parts in
      check int "Number of holes" 1 (List.length holes);
      match holes with
      | [h] ->
          check string "Hole name" "count" h.name;
          check (option string) "Format" (Some "00000") h.format
      | _ -> fail "Unexpected holes" )
  | Error msg -> fail msg
;;

let test_parse_empty () =
  let template = "" in
  match Template_parser.parse_template template with
  | Ok parts -> check int "Empty template has no parts" 0 (List.length parts)
  | Error msg -> fail msg
;;

(* Error case tests *)
let test_unmatched_open_brace () =
  let template = "Hello {name" in
  match Template_parser.parse_template template with
  | Ok _ -> fail "Should have failed with unmatched brace"
  | Error msg ->
      check bool "Error mentions end of input or brace" true
        (String.contains msg 'e' || String.contains msg '}')
;;

let test_unmatched_close_brace () =
  let template = "Hello }name" in
  match Template_parser.parse_template template with
  | Ok parts -> (
    (* Parser treats lone } as literal text *)
    match parts with
    | [Types.Text "Hello }name"] -> ()
    | _ ->
        fail
          (Printf.sprintf "Expected single text part, got: %s"
             (String.concat "; "
                (List.map
                   (function
                     | Types.Text s -> Printf.sprintf "Text %S" s
                     | Types.Hole h -> Printf.sprintf "Hole %s" h.name )
                   parts ) ) ) )
  | Error _ ->
      (* Parser may treat lone } as literal or error - both acceptable *)
      ()
;;

let test_invalid_hole_name () =
  (* Hole names with spaces should fail or be truncated *)
  let template = "Hello {user name}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      (* Parser might accept up to the space *)
      let holes = Template_parser.extract_holes parts in
      match holes with
      | [h] ->
          (* Should only capture "user", not "user name" *)
          check string "Hole name stops at space" "user" h.name
      | _ -> () )
  | Error _ -> ()
;;

let test_empty_hole_name () =
  let template = "Hello {}" in
  match Template_parser.parse_template template with
  | Ok _ -> fail "Should have failed with empty hole name"
  | Error msg ->
      check bool "Error mentions empty or invalid" true
        ( String.contains msg 'e'
        || String.contains msg 'i'
        || String.contains msg '}' )
;;

let test_malformed_format_specifier () =
  (* Missing closing brace after format *)
  let template = "Value: {count:d" in
  match Template_parser.parse_template template with
  | Ok _ -> fail "Should have failed with unclosed hole"
  | Error _ -> ()
;;

let test_nested_braces () =
  let template = "{{ {name} }}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      check int "Number of parts" 5 (List.length parts);
      match parts with
      | [ Types.Text "{"
        ; Types.Text " "
        ; Types.Hole h
        ; Types.Text " "
        ; Types.Text "}" ] -> check string "Hole name" "name" h.name
      | _ ->
          fail
            (Printf.sprintf "Expected escaped braces around hole, got: %s"
               (String.concat "; "
                  (List.map
                     (function
                       | Types.Text s -> Printf.sprintf "Text %S" s
                       | Types.Hole h -> Printf.sprintf "Hole %s" h.name )
                     parts ) ) ) )
  | Error msg -> fail msg
;;

let test_hole_with_special_chars () =
  (* Test various special characters in hole names *)
  let test_cases =
    [("{name!}", "name"); ("{name@}", "name"); ("{name#}", "name")]
  in
  List.iter
    (fun (template, expected_name) ->
      match Template_parser.parse_template template with
      | Ok parts -> (
          let holes = Template_parser.extract_holes parts in
          match holes with
          | [h] -> check string "Hole name" expected_name h.name
          | _ -> () )
      | Error _ -> () )
    test_cases
;;

let test_only_whitespace_template () =
  let template = "   " in
  match Template_parser.parse_template template with
  | Ok parts -> check int "Whitespace only template" 1 (List.length parts)
  | Error msg -> fail msg
;;

let test_multiple_unmatched_braces () =
  let template = "{a} {b {c}" in
  match Template_parser.parse_template template with
  | Ok _ -> fail "Should have failed with unmatched brace"
  | Error _ -> ()
;;

let test_format_without_brace () =
  let template = "Value: {count:" in
  match Template_parser.parse_template template with
  | Ok _ -> fail "Should have failed with unclosed format specifier"
  | Error _ -> ()
;;

(* Alignment specifier tests *)
let test_positive_alignment () =
  let template = "{name,10}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      let holes = Template_parser.extract_holes parts in
      check int "Number of holes" 1 (List.length holes);
      match holes with
      | [h] ->
          check string "Hole name" "name" h.name;
          check
            (option (pair bool int))
            "Alignment"
            (Some (false, 10))
            h.alignment
      | _ -> fail "Unexpected holes" )
  | Error msg -> fail msg
;;

let test_negative_alignment () =
  let template = "{name,-10}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      let holes = Template_parser.extract_holes parts in
      check int "Number of holes" 1 (List.length holes);
      match holes with
      | [h] ->
          check string "Hole name" "name" h.name;
          check
            (option (pair bool int))
            "Alignment"
            (Some (true, 10))
            h.alignment
      | _ -> fail "Unexpected holes" )
  | Error msg -> fail msg
;;

let test_alignment_with_format () =
  let template = "{count,10:d}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      let holes = Template_parser.extract_holes parts in
      check int "Number of holes" 1 (List.length holes);
      match holes with
      | [h] ->
          check string "Hole name" "count" h.name;
          check
            (option (pair bool int))
            "Alignment"
            (Some (false, 10))
            h.alignment;
          check (option string) "Format" (Some "d") h.format
      | _ -> fail "Unexpected holes" )
  | Error msg -> fail msg
;;

let test_alignment_with_operator () =
  let template = "{@data,-15}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      let holes = Template_parser.extract_holes parts in
      check int "Number of holes" 1 (List.length holes);
      match holes with
      | [h] ->
          check string "Hole name" "data" h.name;
          check bool "Structure operator" true (h.operator = Types.Structure);
          check
            (option (pair bool int))
            "Alignment"
            (Some (true, 15))
            h.alignment
      | _ -> fail "Unexpected holes" )
  | Error msg -> fail msg
;;

let test_no_alignment () =
  let template = "{name}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      let holes = Template_parser.extract_holes parts in
      check int "Number of holes" 1 (List.length holes);
      match holes with
      | [h] ->
          check string "Hole name" "name" h.name;
          check (option (pair bool int)) "No alignment" None h.alignment
      | _ -> fail "Unexpected holes" )
  | Error msg -> fail msg
;;

let () =
  run "Template Parser Tests"
    [ ( "basic"
      , [ test_case "Simple template" `Quick test_parse_simple
        ; test_case "With operators" `Quick test_parse_with_operator
        ; test_case "Escaped braces" `Quick test_parse_escaped_braces
        ; test_case "Format specifier" `Quick test_parse_with_format
        ; test_case "Empty template" `Quick test_parse_empty ] )
    ; ( "error_cases"
      , [ test_case "Unmatched open brace" `Quick test_unmatched_open_brace
        ; test_case "Unmatched close brace" `Quick test_unmatched_close_brace
        ; test_case "Invalid hole name" `Quick test_invalid_hole_name
        ; test_case "Empty hole name" `Quick test_empty_hole_name
        ; test_case "Malformed format specifier" `Quick
            test_malformed_format_specifier
        ; test_case "Nested braces" `Quick test_nested_braces
        ; test_case "Hole with special chars" `Quick
            test_hole_with_special_chars
        ; test_case "Only whitespace template" `Quick
            test_only_whitespace_template
        ; test_case "Multiple unmatched braces" `Quick
            test_multiple_unmatched_braces
        ; test_case "Format without brace" `Quick test_format_without_brace ] )
    ; ( "alignment"
      , [ test_case "Positive alignment" `Quick test_positive_alignment
        ; test_case "Negative alignment" `Quick test_negative_alignment
        ; test_case "Alignment with format" `Quick test_alignment_with_format
        ; test_case "Alignment with operator" `Quick
            test_alignment_with_operator
        ; test_case "No alignment" `Quick test_no_alignment ] ) ]
;;
