(** PPX logging example - demonstrates structured logging with explicit
    converters *)

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

  (* Use Log module directly with explicit converters *)

  (* Verbose level - very detailed tracing *)
  let (trace_id : string) = "trace-abc-123" in
  Log.verbose "Entering function with trace_id {trace_id}"
    [("trace_id", Runtime_helpers.Converter.string trace_id)];

  (* Debug level - developer information *)
  let (config_value : int) = 42 in
  let (debug_mode : bool) = true in
  Log.debug "Configuration: value={config_value}, debug={debug_mode}"
    [ ("config_value", Runtime_helpers.Converter.int config_value)
    ; ("debug_mode", Runtime_helpers.Converter.bool debug_mode) ];

  (* Information level - normal operations *)
  let (user : string) = "alice" in
  let (action : string) = "login" in
  Log.information "User {user} performed {action}"
    [ ("user", Runtime_helpers.Converter.string user)
    ; ("action", Runtime_helpers.Converter.string action) ];

  (* Process some data *)
  let (items : string list) = ["item1"; "item2"; "item3"] in
  let (count : int) = List.length items in
  Log.information "Processing {count} items"
    [("count", Runtime_helpers.Converter.int count)];

  List.iter
    (fun (item : string) ->
      Log.debug "Processing item: {item}"
        [("item", Runtime_helpers.Converter.string item)] )
    items;

  (* Warning level - suspicious conditions *)
  let (threshold : int) = 100 in
  let (current_value : int) = 150 in
  if current_value > threshold then
    Log.warning "Value {current_value} exceeds threshold {threshold}"
      [ ("current_value", Runtime_helpers.Converter.int current_value)
      ; ("threshold", Runtime_helpers.Converter.int threshold) ];

  (* Error level - actual errors *)
  let (error_code : int) = 500 in
  let (error_message : string) = "Internal Server Error" in
  Log.error "Error {error_code}: {error_message}"
    [ ("error_code", Runtime_helpers.Converter.int error_code)
    ; ("error_message", Runtime_helpers.Converter.string error_message) ];

  (* Fatal level - system failures *)
  let (critical_component : string) = "database" in
  Log.fatal "Critical failure in {critical_component}"
    [("critical_component", Runtime_helpers.Converter.string critical_component)];

  (* Multiple variables in one message *)
  let (ip_address : string) = "192.168.1.1" in
  let (port : int) = 8080 in
  let (protocol : string) = "https" in
  Log.information "Connection from {ip_address}:{port} using {protocol}"
    [ ("ip_address", Runtime_helpers.Converter.string ip_address)
    ; ("port", Runtime_helpers.Converter.int port)
    ; ("protocol", Runtime_helpers.Converter.string protocol) ];

  (* Static message without variables *)
  Log.information "Application shutdown initiated" [];

  (* Cleanup *)
  Log.close_and_flush ();
  print_endline "\nPPX logging example completed!"
;;
