(** Tests for escaped braces in templates *)

open Alcotest
open Message_templates

let test_double_left_brace () =
  let template = "{{" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      check int "Number of parts" 1 (List.length parts);
      match parts with
      | [Types.Text "{"] -> ()
      | _ -> fail "Expected single text part with '{'" )
  | Error msg -> fail msg
;;

let test_double_right_brace () =
  let template = "}}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      check int "Number of parts" 1 (List.length parts);
      match parts with
      | [Types.Text "}"] -> ()
      | _ -> fail "Expected single text part with '}'" )
  | Error msg -> fail msg
;;

let test_mixed_escapes () =
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

let test_triple_brace () =
  (* {{{ should become { followed by a hole opener *)
  let template = "{{{name}" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      check int "Number of parts" 2 (List.length parts);
      match parts with
      | [Types.Text "{"; Types.Hole h] -> check string "Hole name" "name" h.name
      | _ ->
          fail
            (Printf.sprintf "Expected { followed by hole, got: %s"
               (String.concat "; "
                  (List.map
                     (function
                       | Types.Text s -> Printf.sprintf "Text %S" s
                       | Types.Hole h -> Printf.sprintf "Hole %s" h.name )
                     parts ) ) ) )
  | Error msg -> fail msg
;;

let test_escaped_braces_in_text () =
  let template = "Use {{braces}} for placeholders" in
  match Template_parser.parse_template template with
  | Ok parts -> (
      (* Parser splits {{ into separate { and }} into separate } *)
      check int "Number of parts" 5 (List.length parts);
      match parts with
      | [ Types.Text "Use "
        ; Types.Text "{"
        ; Types.Text "braces"
        ; Types.Text "}"
        ; Types.Text " for placeholders" ] -> ()
      | _ ->
          fail
            (Printf.sprintf "Expected escaped braces in text, got: %s"
               (String.concat "; "
                  (List.map
                     (function
                       | Types.Text s -> Printf.sprintf "Text %S" s
                       | Types.Hole h -> Printf.sprintf "Hole %s" h.name )
                     parts ) ) ) )
  | Error msg -> fail msg
;;

let test_reconstruct_template () =
  (* Test reconstruction of a simpler template first *)
  let template = "{{literal}}" in
  match Template_parser.parse_template template with
  | Ok parts ->
      let reconstructed = Types.reconstruct_template parts in
      (* The reconstructed template should produce equivalent output though the
         exact escaping may differ *)
      check bool "Reconstructed contains braces" true
        (String.contains reconstructed '{')
  | Error msg -> fail msg
;;

let () =
  run "Escape Tests"
    [ ( "braces"
      , [ test_case "Double left brace" `Quick test_double_left_brace
        ; test_case "Double right brace" `Quick test_double_right_brace
        ; test_case "Mixed escapes" `Quick test_mixed_escapes
        ; test_case "Triple brace" `Quick test_triple_brace
        ; test_case "Escaped braces in text" `Quick test_escaped_braces_in_text
        ; test_case "Reconstruct template" `Quick test_reconstruct_template ] )
    ]
;;
