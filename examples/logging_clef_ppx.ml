(** CLEF/JSON structured logging with PPX - clean syntax + pure JSON output *)

open Message_templates

let () =
  (* Clean up any previous output file *)
  (try Sys.remove "output.clef.json" with Sys_error _ -> ());

  (* Create a JSON file sink for pure CLEF output *)
  let json_sink_instance = Json_sink.create "output.clef.json" in
  let json_sink =
    { Composite_sink.emit_fn=
        (fun event -> Json_sink.emit json_sink_instance event)
    ; flush_fn= (fun () -> Json_sink.flush json_sink_instance)
    ; close_fn= (fun () -> Json_sink.close json_sink_instance)
    ; min_level= None }
  in

  (* Configure the logger with JSON output *)
  let logger = Logger.create ~min_level:Level.Verbose ~sinks:[json_sink] in

  Log.set_logger logger;

  (* Use PPX extensions for cleaner syntax with JSON output *)

  (* Verbose level - detailed tracing *)
  let trace_id = "trace-abc-123" in
  [%log.verbose "Detailed trace: trace_id={trace_id}"];

  (* Debug level - developer information *)
  let config_value = 42 in
  let debug_mode = true in
  [%log.debug "Configuration: value={config_value}, debug={debug_mode}"];

  (* Information level - normal operations *)
  let user = "alice" in
  let action = "login" in
  [%log.information "User {user} performed {action}"];

  (* Request processing with context *)
  Log_context.with_property "RequestId" (`String "req-xyz-789") (fun () ->
      let endpoint = "/api/users" in
      let method_ = "POST" in
      [%log.debug "Processing {method_} request to {endpoint}"];

      (* Simulate work *)
      Unix.sleepf 0.01;

      let status_code = 201 in
      let duration_ms = 15.5 in
      [%log.information
        "Request completed: status={status_code}, duration={duration_ms}ms"] );

  (* Warning level *)
  let threshold = 100 in
  let current_value = 150 in
  [%log.warning "Value {current_value} exceeds threshold {threshold}"];

  (* Error level *)
  let error_code = "DB_CONNECTION_TIMEOUT" in
  let retry_count = 3 in
  [%log.error
    "Database connection failed: code={error_code}, retry={retry_count}"];

  (* Fatal level *)
  let component = "payment-service" in
  [%log.fatal "Critical failure in {component}"];

  (* Multiple variables in one message *)
  let ip_address = "192.168.1.1" in
  let port = 8080 in
  let protocol = "https" in
  [%log.information "Connection from {ip_address}:{port} using {protocol}"];

  (* Application lifecycle *)
  [%log.information "Application shutdown initiated"];

  (* Cleanup *)
  Log.close_and_flush ();

  (* Display the output *)
  print_endline "CLEF/JSON with PPX logging example completed!";
  print_endline "";
  print_endline "Output file: output.clef.json";
  print_endline "";
  print_endline "Sample output:";
  let ic = open_in "output.clef.json" in
  let lines = ref [] in
  ( try
      while true do
        lines := input_line ic :: !lines
      done
    with End_of_file -> () );
  close_in ic;
  (* Show first 5 lines *)
  let all_lines = List.rev !lines in
  List.iteri
    (fun i line ->
      if i < 5 then
        print_endline ("  " ^ line) )
    all_lines
;;
