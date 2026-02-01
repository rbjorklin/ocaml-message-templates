(** CLEF/JSON structured logging example - outputs pure JSON format *)

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
    ; close_fn= (fun () -> Json_sink.close json_sink_instance) }
  in

  (* Configure the logger with JSON output *)
  let logger = Logger.create ~min_level:Level.Debug ~sinks:[json_sink] in

  Log.set_logger logger;

  (* Log various events with structured data *)
  Log.information "Application started"
    [ ("application", `String "MyApp")
    ; ("version", `String "1.0.0")
    ; ("environment", `String "production") ];

  (* User login with context *)
  let user_id = "user-123" in
  let username = "alice" in
  let ip_address = "192.168.1.1" in
  Log.information "User {username} logged in from {ip_address}"
    [ ("user_id", `String user_id)
    ; ("username", `String username)
    ; ("ip_address", `String ip_address)
    ; ("auth_method", `String "password") ];

  (* Request processing with nested context *)
  Log_context.with_property "RequestId" (`String "req-abc-456") (fun () ->
      Log.debug "Processing request"
        [ ("endpoint", `String "/api/users")
        ; ("method", `String "POST")
        ; ("body_size", `Int 1024) ];

      (* Simulate some work *)
      Unix.sleepf 0.01;

      Log.information "Request completed"
        [ ("status_code", `Int 201)
        ; ("duration_ms", `Float 12.5)
        ; ("cache_hit", `Bool false) ] );

  (* Error with details *)
  let error_code = "DB_CONNECTION_TIMEOUT" in
  let retry_count = 3 in
  Log.error "Database connection failed"
    [ ("error_code", `String error_code)
    ; ("retry_count", `Int retry_count)
    ; ("max_retries", `Int 3)
    ; ("database", `String "users_db")
    ; ("host", `String "db-primary.internal") ];

  (* Performance metrics *)
  Log.information "Performance metrics"
    [ ("memory_mb", `Float 512.5)
    ; ("cpu_percent", `Float 45.2)
    ; ("requests_per_sec", `Int 150)
    ; ("active_connections", `Int 42) ];

  (* Application shutdown *)
  Log.information "Application shutting down"
    [ ("uptime_seconds", `Int 3600)
    ; ("requests_processed", `Int 10000)
    ; ("errors_total", `Int 12) ];

  (* Cleanup *)
  Log.close_and_flush ();

  (* Display the output *)
  print_endline "CLEF/JSON structured logging example completed!";
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
