(** Tests for PPX log level extensions *)

open Alcotest
open Message_templates

let temp_file () =
  Filename.temp_file "test_ppx_log_" ".log"

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let contains substr str =
  let substr_len = String.length substr in
  let str_len = String.length str in
  if substr_len > str_len then false
  else
    let rec check i =
      if i > str_len - substr_len then false
      else if String.sub str i substr_len = substr then true
      else check (i + 1)
    in
    check 0

let setup_logger path =
  let logger =
    Configuration.create ()
    |> Configuration.debug
    |> Configuration.write_to_file path
    |> Configuration.create_logger
  in
  Log.set_logger logger

let test_ppx_information () =
  let path = temp_file () in
  setup_logger path;
  
  let user = "alice" in
  let action = "login" in
  
  (* Use the PPX extension *)
  [%log.information "User {user} performed {action}"];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Message logged" true (contains "User {user} performed {action}" content);
  check bool "User value logged" true (contains "alice" content);
  check bool "Action value logged" true (contains "login" content);
  
  Sys.remove path

let test_ppx_warning () =
  let path = temp_file () in
  setup_logger path;
  
  let count = 42 in
  
  [%log.warning "Warning: {count} items failed validation"];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Warning message logged" true (contains "Warning: {count} items failed validation" content);
  check bool "Count value logged" true (contains "42" content);
  
  Sys.remove path

let test_ppx_error () =
  let path = temp_file () in
  setup_logger path;
  
  let error_code = 500 in
  let message = "Internal Server Error" in
  
  [%log.error "Error {error_code}: {message}"];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Error message logged" true (contains "Error {error_code}: {message}" content);
  check bool "Error code logged" true (contains "500" content);
  check bool "Message logged" true (contains "Internal Server Error" content);
  
  Sys.remove path

let test_ppx_debug () =
  let path = temp_file () in
  setup_logger path;
  
  let debug_info = "connection established" in
  
  [%log.debug "Debug: {debug_info}"];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Debug message logged" true (contains "Debug: {debug_info}" content);
  check bool "Debug info logged" true (contains "connection established" content);
  
  Sys.remove path

let test_ppx_verbose () =
  let path = temp_file () in
  (* Use verbose level logger *)
  let logger =
    Configuration.create ()
    |> Configuration.verbose
    |> Configuration.write_to_file path
    |> Configuration.create_logger
  in
  Log.set_logger logger;
  
  let detail = "verbose detail here" in
  
  [%log.verbose "Verbose: {detail}"];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Verbose message logged" true (contains "Verbose: {detail}" content);
  check bool "Detail logged" true (contains "verbose detail here" content);
  
  Sys.remove path

let test_ppx_fatal () =
  let path = temp_file () in
  setup_logger path;
  
  let reason = "critical failure" in
  
  [%log.fatal "Fatal error: {reason}"];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Fatal message logged" true (contains "Fatal error: {reason}" content);
  check bool "Reason logged" true (contains "critical failure" content);
  
  Sys.remove path

let test_ppx_multiple_variables () =
  let path = temp_file () in
  setup_logger path;
  
  let user = "bob" in
  let ip = "192.168.1.1" in
  let port = 8080 in
  
  [%log.information "User {user} connected from {ip}:{port}"];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Message logged" true (contains "User {user} connected from {ip}:{port}" content);
  check bool "User logged" true (contains "bob" content);
  check bool "IP logged" true (contains "192.168.1.1" content);
  check bool "Port logged" true (contains "8080" content);
  
  Sys.remove path

let test_ppx_no_variables () =
  let path = temp_file () in
  setup_logger path;
  
  [%log.information "Application started successfully"];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Message logged" true (contains "Application started successfully" content);
  
  Sys.remove path

let () =
  run "PPX Log Level Tests" [
    "basic_levels", [
      test_case "PPX information level" `Quick test_ppx_information;
      test_case "PPX warning level" `Quick test_ppx_warning;
      test_case "PPX error level" `Quick test_ppx_error;
      test_case "PPX debug level" `Quick test_ppx_debug;
      test_case "PPX verbose level" `Quick test_ppx_verbose;
      test_case "PPX fatal level" `Quick test_ppx_fatal;
    ];
    "variables", [
      test_case "PPX multiple variables" `Quick test_ppx_multiple_variables;
      test_case "PPX no variables" `Quick test_ppx_no_variables;
    ];
  ]
