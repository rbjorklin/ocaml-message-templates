(** CLEF/JSON structured logging with automatic deriving

    This example demonstrates how to use ppx_deriving_yojson with CLEF output
    for automatic JSON serialization of your custom types.

    The output is pure CLEF/JSON format suitable for ingestion into structured
    logging systems like Seq, Elasticsearch, or Splunk. *)

open Message_templates

(* Define domain types with automatic JSON deriving *)
type user =
  { id: int
  ; username: string
  ; email: string
  ; department: string }
[@@deriving yojson]

type request_method =
  | GET
  | POST
  | PUT
  | DELETE
[@@deriving yojson]

type response_status =
  | Success
  | ClientError of int
  | ServerError of int
[@@deriving yojson]

type http_request =
  { request_id: string
  ; user: user
  ; method_: request_method
  ; path: string
  ; user_agent: string option }
[@@deriving yojson]

type http_response =
  { status: response_status
  ; duration_ms: float
  ; bytes_sent: int }
[@@deriving yojson]

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

  (* Create sample users - automatic JSON conversion with user_to_yojson *)
  let alice =
    { id= 1
    ; username= "alice"
    ; email= "alice@company.com"
    ; department= "Engineering" }
  in

  let bob =
    {id= 2; username= "bob"; email= "bob@company.com"; department= "Marketing"}
  in

  (* Verbose level - detailed tracing with full user objects *)
  Log.verbose "Processing user context" [("current_user", user_to_yojson alice)];

  (* Simulate login - automatic conversion *)
  Log.information "User logged in successfully" [("user", user_to_yojson alice)];

  (* Simulate HTTP request processing *)
  let request =
    { request_id= "req-abc-123"
    ; user= alice
    ; method_= POST
    ; path= "/api/orders"
    ; user_agent= Some "Mozilla/5.0" }
  in

  Log_context.with_property "RequestId" (`String request.request_id) (fun () ->
      Log.debug "Processing HTTP request"
        [("request", http_request_to_yojson request)];

      (* Simulate work *)
      Unix.sleepf 0.01;

      (* Successful response *)
      let success_response =
        {status= Success; duration_ms= 45.3; bytes_sent= 1024}
      in

      Log.information "Request completed"
        [ ("request", http_request_to_yojson request)
        ; ("response", http_response_to_yojson success_response) ] );

  (* Simulate another request with error *)
  let error_request =
    { request_id= "req-def-456"
    ; user= bob
    ; method_= GET
    ; path= "/api/users/99999"
    ; user_agent= None }
  in

  let error_response =
    {status= ClientError 404; duration_ms= 12.5; bytes_sent= 0}
  in

  Log.warning "Resource not found"
    [ ("request", http_request_to_yojson error_request)
    ; ("response", http_response_to_yojson error_response) ];

  (* Simulate database error with server error response *)
  let db_error_response =
    {status= ServerError 500; duration_ms= 2500.0; bytes_sent= 0}
  in

  Log.error "Database connection timeout"
    [ ("request_id", `String "req-ghi-789")
    ; ("user", user_to_yojson alice)
    ; ("response", http_response_to_yojson db_error_response)
    ; ("retry_count", `Int 3) ];

  (* Fatal error - critical system failure *)
  Log.fatal "Payment service unavailable"
    [ ("service", `String "payment-processor")
    ; ("affected_users", `Int 2)
    ; ("users", `List [user_to_yojson alice; user_to_yojson bob]) ];

  (* Application shutdown *)
  Log.information "Application shutdown initiated" [];

  (* Cleanup *)
  Log.close_and_flush ();

  (* Display summary *)
  print_endline "CLEF/JSON logging with deriving completed!";
  print_endline "";
  print_endline "Output file: output.clef.json";
  print_endline "";
  print_endline "Sample CLEF events:";
  let ic = open_in "output.clef.json" in
  let lines = ref [] in
  ( try
      while true do
        lines := input_line ic :: !lines
      done
    with End_of_file -> () );
  close_in ic;
  (* Show first 5 lines formatted *)
  let all_lines = List.rev !lines in
  List.iteri
    (fun i line ->
      if i < 5 then (
        print_endline ("  Event " ^ string_of_int (i + 1) ^ ":");
        (* Pretty print the JSON *)
        try
          let json = Yojson.Safe.from_string line in
          print_endline ("    " ^ Yojson.Safe.pretty_to_string json)
        with _ -> print_endline ("    " ^ line) ) )
    all_lines
;;
