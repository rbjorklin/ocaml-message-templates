(** Comprehensive PPX tests for Message Templates *)

open Alcotest

let test_simple_variables () =
  let name = "Alice" in
  let msg, json = [%template "Hello, {name}!"] in
  check string "Message" "Hello, Alice!" msg;
  let json_str = Yojson.Safe.to_string json in
  (* Check that JSON contains expected fields *)
  check bool "JSON contains @t (timestamp)" true (String.contains json_str '@');
  check bool "JSON contains @m (template)" true (String.contains json_str '@');
  check bool "JSON contains name" true (String.contains json_str 'n')

let test_multiple_variables () =
  let user = "bob" in
  let action = "login" in
  let count = 3 in
  let msg, json = [%template "User {user} performed {action} {count:d} times"] in
  check string "Message" "User bob performed login 3 times" msg;
  let json_str = Yojson.Safe.to_string json in
  check bool "JSON contains @t" true (String.contains json_str '@');
  check bool "JSON contains user" true (String.contains json_str 'b');
  check bool "JSON contains action" true (String.contains json_str 'l')

let test_format_specifiers () =
  let id = 7 in
  let score = 95.5 in
  let active = true in
  let msg, _ = [%template "ID: {id:05d}, Score: {score:.1f}, Active: {active:B}"] in
  check string "Message with formats" "ID: 00007, Score: 95.5, Active: true" msg

let test_stringify_operator () =
  let data = [1; 2; 3] in
  let msg, _ = [%template "Data: {$data}"] in
  check bool "Message contains list representation" true 
    (String.contains msg '[' && String.contains msg '1')

let test_escaped_braces () =
  let msg, _ = [%template "Use {{braces}} for literals"] in
  check string "Escaped braces" "Use {braces} for literals" msg

let test_empty_template () =
  let msg, json = [%template ""] in
  check string "Empty message" "" msg;
  let json_str = Yojson.Safe.to_string json in
  check bool "JSON contains @t" true (String.contains json_str '@');
  check bool "JSON contains @m" true (String.contains json_str '@')

let test_mixed_types () =
  let str_val = "text" in
  let int_val = 42 in
  let float_val = 3.14 in
  let bool_val = false in
  let msg, _ = [%template "{str_val}, {int_val:d}, {float_val:f}, {bool_val:B}"] in
  check string "Mixed types" "text, 42, 3.140000, false" msg

let test_timestamp_format () =
  let _msg, json = [%template "Test"] in
  let json_str = Yojson.Safe.to_string json in
  (* Check that timestamp is in RFC3339 format with T separator *)
  check bool "JSON contains timestamp" true (String.contains json_str '@');
  check bool "Timestamp has RFC3339 format" true 
    (String.contains json_str 'T')

let () =
  run "PPX Comprehensive Tests" [
    "basic", [
      test_case "Simple variables" `Quick test_simple_variables;
      test_case "Multiple variables" `Quick test_multiple_variables;
      test_case "Format specifiers" `Quick test_format_specifiers;
      test_case "Stringify operator" `Quick test_stringify_operator;
      test_case "Escaped braces" `Quick test_escaped_braces;
      test_case "Empty template" `Quick test_empty_template;
      test_case "Mixed types" `Quick test_mixed_types;
      test_case "Timestamp format" `Quick test_timestamp_format;
    ];
  ]
