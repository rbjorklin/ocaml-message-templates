(** PPX logging example - demonstrates level-aware PPX extensions *)

open Message_templates

let () =
  (* Configure the logger *)
  let logger =
    Configuration.create ()
    |> Configuration.verbose
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.write_to_file "ppx_example.log"
    |> Configuration.create_logger
  in

  Log.set_logger logger;

  (* Use PPX extensions for cleaner syntax *)

  (* Verbose level - very detailed tracing *)
  let trace_id = "trace-abc-123" in
  [%log.verbose "Entering function with trace_id {trace_id}"];

  (* Debug level - developer information *)
  let config_value = 42 in
  let debug_mode = true in
  [%log.debug "Configuration: value={config_value}, debug={debug_mode}"];

  (* Information level - normal operations *)
  let user = "alice" in
  let action = "login" in
  [%log.information "User {user} performed {action}"];

  (* Process some data *)
  let items = ["item1"; "item2"; "item3"] in
  let count = List.length items in
  [%log.information "Processing {count} items"];

  List.iter (fun item -> [%log.debug "Processing item: {item}"]) items;

  (* Warning level - suspicious conditions *)
  let threshold = 100 in
  let current_value = 150 in
  if current_value > threshold then
    [%log.warning "Value {current_value} exceeds threshold {threshold}"];

  (* Error level - actual errors *)
  let error_code = 500 in
  let error_message = "Internal Server Error" in
  [%log.error "Error {error_code}: {error_message}"];

  (* Fatal level - system failures *)
  let critical_component = "database" in
  [%log.fatal "Critical failure in {critical_component}"];

  (* Multiple variables in one message *)
  let ip_address = "192.168.1.1" in
  let port = 8080 in
  let protocol = "https" in
  [%log.information "Connection from {ip_address}:{port} using {protocol}"];

  (* Static message without variables *)
  [%log.information "Application shutdown initiated"];

  (* Cleanup *)
  Log.close_and_flush ();
  print_endline "\nPPX logging example completed!"
;;
