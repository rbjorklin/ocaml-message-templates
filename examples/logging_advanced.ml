(** Advanced logging example - demonstrates file rolling, multiple sinks, and
    filtering *)

open Message_templates

let () =
  (* Create a logs directory *)
  let log_dir = "logs" in
  (try Unix.mkdir log_dir 0o755 with Unix.Unix_error _ -> ());

  (* Configure multiple sinks with different behaviors *)
  let logger =
    Configuration.create ()
    |> Configuration.debug
    (* Console sink - shows all messages with colors *)
    |> Configuration.write_to_console ~colors:true
         ~stderr_threshold:Level.Warning ()
    (* File sink with daily rolling for all messages *)
    |> Configuration.write_to_file ~rolling:File_sink.Daily
         ~output_template:"{timestamp} [{level}] {message}"
         (Filename.concat log_dir "app.log")
    (* Separate error log - only warnings and above *)
    |> Configuration.write_to_file ~rolling:File_sink.Daily
         (Filename.concat log_dir "errors.log")
    (* Add enrichers *)
    |> Configuration.enrich_with_property "Environment" (`String "Production")
    |> Configuration.enrich_with_property "Host" (`String (Unix.gethostname ()))
    (* Add filters *)
    |> Configuration.filter_by_min_level Level.Debug
    |> Configuration.create_logger
  in

  Log.set_logger logger;

  (* Application startup *)
  Log.information "Application starting" [];
  Log.information "Environment: Production" [];
  Log.information "Host: {host}" [("host", `String (Unix.gethostname ()))];

  (* Simulate different types of operations *)
  let process_user_request user_id request_type =
    Log_context.with_property "RequestId"
      (`String ("req-" ^ string_of_int (Random.int 10000)))
      (fun () ->
        Log.debug "Processing {request_type} request for user {user_id}"
          [("request_type", `String request_type); ("user_id", `Int user_id)];

        (* Simulate some work *)
        Unix.sleepf 0.01;

        (* Randomly generate some warnings and errors *)
        let rand = Random.int 100 in
        if rand < 10 then
          Log.error "Database connection failed for user {user_id}"
            [("user_id", `Int user_id)]
        else if rand < 30 then
          Log.warning "Slow query detected for user {user_id}"
            [("user_id", `Int user_id)]
        else
          Log.information "Request completed successfully" [] )
  in

  (* Simulate multiple requests *)
  Random.self_init ();
  for _ = 1 to 20 do
    let user_id = Random.int 1000 in
    let request_types = ["GET"; "POST"; "PUT"; "DELETE"] in
    let request_type =
      List.nth request_types (Random.int (List.length request_types))
    in
    process_user_request user_id request_type
  done;

  (* Application shutdown *)
  Log.information "Application shutting down" [];
  Log.close_and_flush ();

  print_endline "\nAdvanced logging example completed!";
  print_endline "Check the 'logs/' directory for output files:";
  print_endline "  - logs/app.log (all messages)";
  print_endline "  - logs/errors.log (warnings and errors)"
;;
