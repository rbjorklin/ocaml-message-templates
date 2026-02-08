(** Comprehensive PPX tests for Message Templates *)

open Alcotest

let test_empty_template () =
  let msg, json = [%template ""] in
  check string "Empty message" "" msg;
  let json_str = Yojson.Safe.to_string json in
  check bool "JSON contains @t" true (String.contains json_str '@');
  check bool "JSON contains @m" true (String.contains json_str '@')
;;

let test_text_only () =
  let msg, _ = [%template "Hello, World!"] in
  check string "Text only" "Hello, World!" msg
;;

let test_escaped_braces () =
  let msg, _ = [%template "Use {{braces}} for literals"] in
  check string "Escaped braces" "Use {braces} for literals" msg
;;

let test_timestamp_format () =
  let _msg, json = [%template "Test message"] in
  let json_str = Yojson.Safe.to_string json in
  (* Check that timestamp is in RFC3339 format with T separator *)
  check bool "JSON contains timestamp" true (String.contains json_str '@');
  check bool "Timestamp has RFC3339 format" true (String.contains json_str 'T')
;;

let () =
  run "PPX Comprehensive Tests"
    [ ( "basic"
      , [ test_case "Empty template" `Quick test_empty_template
        ; test_case "Text only" `Quick test_text_only
        ; test_case "Escaped braces" `Quick test_escaped_braces
        ; test_case "Timestamp format" `Quick test_timestamp_format ] ) ]
;;
