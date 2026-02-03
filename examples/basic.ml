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

  (* Test 3: Template with variables *)
  let username : string = "alice" in
  let ip : string = "192.168.1.1" in
  let msg3, json3 = [%template "User {username} logged in from {ip}"] in
  Printf.printf "Test 3 - Template with variables:\n";
  Printf.printf "  Message: %s\n" msg3;
  Printf.printf "  JSON: %s\n\n" (Yojson.Safe.to_string json3);

  Printf.printf "All tests passed!\n"
;;
