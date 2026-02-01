(** Basic logging example - demonstrates core logging features *)

open Message_templates

let () =
  (* Configure the logger *)
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Debug
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.enrich_with_property "Application" (`String "MyApp")
    |> Configuration.enrich_with_property "Version" (`String "1.0.0")
    |> Configuration.create_logger
  in

  Log.set_logger logger;

  (* Basic logging *)
  Log.information "Application started" [];

  (* Logging with variables *)
  let user = "alice" in
  let ip_address = "192.168.1.1" in
  Log.information "User {user} logged in from {ip_address}"
    [("user", `String user); ("ip_address", `String ip_address)];

  (* Different log levels *)
  Log.verbose "This is a verbose message - very detailed" [];
  Log.debug "Debug information for developers" [];
  Log.warning "This is a warning" [];
  Log.error "An error occurred" [];

  (* Logging with exception (simulated) *)
  let simulate_error () =
    try failwith "Something went wrong"
    with exn -> Log.error ~exn "Operation failed" []
  in
  simulate_error ();

  (* Using context for request tracking *)
  Log_context.with_property "RequestId" (`String "req-123-abc") (fun () ->
      Log.information "Processing request" [];
      Log.debug "Request details validated" [];
      Log.information "Request completed" [] );

  (* Multiple context properties *)
  Log_context.with_properties
    [("UserId", `String "user-456"); ("SessionId", `String "sess-789")]
    (fun () -> Log.information "User action performed" []);

  (* Cleanup *)
  Log.close_and_flush ();
  print_endline "\nBasic logging example completed!"
;;
