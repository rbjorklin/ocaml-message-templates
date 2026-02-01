(** Comprehensive example showing Message Templates features *)

let () =
  Printf.printf "Message Templates - Comprehensive Example\n";
  Printf.printf "=========================================\n\n";
  
  (* Example 1: Simple string variables *)
  let username = "alice" in
  let ip_address = "192.168.1.1" in
  let msg1, json1 = [%template "User {username} logged in from {ip_address}"] in
  Printf.printf "Example 1 - Simple string variables:\n";
  Printf.printf "  Message: %s\n" msg1;
  Printf.printf "  JSON: %s\n\n" (Yojson.Safe.to_string json1);
  
  (* Example 2: Using format specifiers for non-string types *)
  let count = 42 in
  let score = 98.5 in
  let active = true in
  let msg2, json2 = [%template "Count: {count:d}, Score: {score:f}, Active: {active:B}"] in
  Printf.printf "Example 2 - Using format specifiers (int, float, bool):\n";
  Printf.printf "  Message: %s\n" msg2;
  Printf.printf "  JSON: %s\n\n" (Yojson.Safe.to_string json2);
  
  (* Example 3: Stringify operator *)
  let data = [1; 2; 3] in
  let msg3, json3 = [%template "Data: {$data}"] in
  Printf.printf "Example 3 - Stringify operator ({$var}):\n";
  Printf.printf "  Message: %s\n" msg3;
  Printf.printf "  JSON: %s\n\n" (Yojson.Safe.to_string json3);
  
  (* Example 4: Format specifiers *)
  let id = 7 in
  let msg4, json4 = [%template "ID: {id:05d}"] in
  Printf.printf "Example 4 - Format specifier:\n";
  Printf.printf "  Message: %s\n" msg4;
  Printf.printf "  JSON: %s\n\n" (Yojson.Safe.to_string json4);
  
  (* Example 5: Mixed content *)
  let user = "bob" in
  let action = "purchased" in
  let items = 3 in
  let msg5, json5 = [%template "{user} {action} {items:d} items"] in
  Printf.printf "Example 5 - Mixed content:\n";
  Printf.printf "  Message: %s\n" msg5;
  Printf.printf "  JSON: %s\n\n" (Yojson.Safe.to_string json5);
  
  Printf.printf "All examples completed successfully!\n"
