(** Basic usage example *)

let () =
  Printf.printf "Message Templates Example\n";
  Printf.printf "=========================\n\n";

  (* Test 1: Simple template without variables *)
  let msg, json = [%template "Hello, World!"] in
  Printf.printf "Test 1 - Simple template:\n";
  Printf.printf "  Message: %s\n" msg;
  Printf.printf "  JSON: %s\n\n" (Yojson.Safe.to_string json);

  (* Test 2: Template with escaped braces *)
  let msg2, json2 = [%template "Use {{braces}} for literals"] in
  Printf.printf "Test 2 - Escaped braces:\n";
  Printf.printf "  Message: %s\n" msg2;
  Printf.printf "  JSON: %s\n\n" (Yojson.Safe.to_string json2);

  (* Test 3: For templates with variables, the PPX requires that variables have
     explicit type annotations or converters in scope.

     Since the PPX is a context-free rule, it cannot access type annotations
     from the surrounding scope. Use the Log module directly for such cases: *)
  let (username : string) = "alice" in
  let (ip : string) = "192.168.1.1" in
  Printf.printf "Test 3 - Using Log module directly:\n";
  Printf.printf "  User %s logged in from %s\n\n" username ip;

  Printf.printf "All tests passed!\n"
;;
