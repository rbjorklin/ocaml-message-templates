(** Tests for Logger module *)

open Alcotest
open Message_templates

let temp_file () = Filename.temp_file "test_logger_" ".log"

let create_file_sink_fn path =
  let sink = File_sink.create path in
  { Composite_sink.emit_fn= (fun event -> File_sink.emit sink event)
  ; flush_fn= (fun () -> File_sink.flush sink)
  ; close_fn= (fun () -> File_sink.close sink) }
;;

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s
;;

let contains substr str =
  let substr_len = String.length substr in
  let str_len = String.length str in
  if substr_len > str_len then
    false
  else
    let rec check i =
      if i > str_len - substr_len then
        false
      else if String.sub str i substr_len = substr then
        true
      else
        check (i + 1)
    in
    check 0
;;

let test_logger_level_filtering () =
  let path = temp_file () in
  let sink = create_file_sink_fn path in
  let logger = Logger.create ~min_level:Level.Warning ~sinks:[sink] in

  (* These should NOT be logged (below Warning) *)
  Logger.verbose logger "Verbose message" [];
  Logger.debug logger "Debug message" [];
  Logger.information logger "Info message" [];

  (* These SHOULD be logged *)
  Logger.warning logger "Warning message" [];
  Logger.error logger "Error message" [];
  Logger.fatal logger "Fatal message" [];

  (* Flush and close *)
  List.iter (fun s -> s.Composite_sink.flush_fn ()) [sink];
  List.iter (fun s -> s.Composite_sink.close_fn ()) [sink];

  let content = read_file path in

  (* Verify low-level messages are NOT in file *)
  check bool "Verbose not logged" false (contains "Verbose message" content);
  check bool "Debug not logged" false (contains "Debug message" content);
  check bool "Info not logged" false (contains "Info message" content);

  (* Verify high-level messages ARE in file *)
  check bool "Warning logged" true (contains "Warning message" content);
  check bool "Error logged" true (contains "Error message" content);
  check bool "Fatal logged" true (contains "Fatal message" content);

  Sys.remove path
;;

let test_logger_is_enabled () =
  let path = temp_file () in
  let sink = create_file_sink_fn path in

  let info_logger = Logger.create ~min_level:Level.Information ~sinks:[sink] in
  let error_logger = Logger.create ~min_level:Level.Error ~sinks:[sink] in

  (* Info logger should have Debug disabled, Information enabled *)
  check bool "Debug disabled for Info logger" false
    (Logger.is_enabled info_logger Level.Debug);
  check bool "Information enabled for Info logger" true
    (Logger.is_enabled info_logger Level.Information);
  check bool "Warning enabled for Info logger" true
    (Logger.is_enabled info_logger Level.Warning);

  (* Error logger should have Warning disabled, Error enabled *)
  check bool "Warning disabled for Error logger" false
    (Logger.is_enabled error_logger Level.Warning);
  check bool "Error enabled for Error logger" true
    (Logger.is_enabled error_logger Level.Error);
  check bool "Fatal enabled for Error logger" true
    (Logger.is_enabled error_logger Level.Fatal);

  List.iter (fun s -> s.Composite_sink.close_fn ()) [sink];
  Sys.remove path
;;

let test_logger_context () =
  let path = temp_file () in
  let sink = create_file_sink_fn path in
  let logger = Logger.create ~min_level:Level.Information ~sinks:[sink] in

  (* Create contextual logger with RequestId *)
  let ctx_logger = Logger.for_context logger "RequestId" (`String "abc-123") in

  (* Log with context *)
  Logger.information ctx_logger "Request processed" [];

  List.iter (fun s -> s.Composite_sink.flush_fn ()) [sink];
  List.iter (fun s -> s.Composite_sink.close_fn ()) [sink];

  let content = read_file path in

  (* Verify message and context property are in file *)
  check bool "Message logged" true (contains "Request processed" content);
  check bool "RequestId in output" true (contains "abc-123" content);

  Sys.remove path
;;

let test_logger_write_with_exception () =
  let path = temp_file () in
  let sink = create_file_sink_fn path in
  let logger = Logger.create ~min_level:Level.Error ~sinks:[sink] in

  (* Create an exception *)
  let exn = Failure "Test exception" in

  (* Log with exception *)
  Logger.error logger ~exn "Error occurred" [];

  List.iter (fun s -> s.Composite_sink.flush_fn ()) [sink];
  List.iter (fun s -> s.Composite_sink.close_fn ()) [sink];

  let content = read_file path in

  (* Verify message is in file *)
  check bool "Error message logged" true (contains "Error occurred" content);

  Sys.remove path
;;

let test_logger_multiple_sinks () =
  let path1 = temp_file () in
  let path2 = temp_file () in

  let sink1 = create_file_sink_fn path1 in
  let sink2 = create_file_sink_fn path2 in

  let logger =
    Logger.create ~min_level:Level.Information ~sinks:[sink1; sink2]
  in

  Logger.information logger "Multi-sink test" [];

  List.iter (fun s -> s.Composite_sink.flush_fn ()) [sink1; sink2];
  List.iter (fun s -> s.Composite_sink.close_fn ()) [sink1; sink2];

  let content1 = read_file path1 in
  let content2 = read_file path2 in

  (* Verify message in both files *)
  check bool "Sink 1 has message" true (contains "Multi-sink test" content1);
  check bool "Sink 2 has message" true (contains "Multi-sink test" content2);

  Sys.remove path1;
  Sys.remove path2
;;

let test_logger_add_min_level_filter () =
  let path = temp_file () in
  let sink = create_file_sink_fn path in

  (* Start with Debug level, but add a Warning filter *)
  let logger = Logger.create ~min_level:Level.Debug ~sinks:[sink] in
  let filtered_logger = Logger.add_min_level_filter logger Level.Warning in

  (* These should NOT be logged due to the additional filter *)
  Logger.debug filtered_logger "Debug after filter" [];
  Logger.information filtered_logger "Info after filter" [];

  (* These SHOULD be logged *)
  Logger.warning filtered_logger "Warning after filter" [];

  List.iter (fun s -> s.Composite_sink.flush_fn ()) [sink];
  List.iter (fun s -> s.Composite_sink.close_fn ()) [sink];

  let content = read_file path in

  check bool "Debug not logged" false (contains "Debug after filter" content);
  check bool "Info not logged" false (contains "Info after filter" content);
  check bool "Warning logged" true (contains "Warning after filter" content);

  Sys.remove path
;;

let test_logger_enricher () =
  let path = temp_file () in
  let sink = create_file_sink_fn path in
  let logger = Logger.create ~min_level:Level.Information ~sinks:[sink] in

  (* Add an enricher that adds a correlation ID *)
  let enricher event =
    let props = Log_event.get_properties event in
    let new_props = ("CorrelationId", `String "corr-456") :: props in
    Log_event.create
      ~timestamp:(Log_event.get_timestamp event)
      ~level:(Log_event.get_level event)
      ~message_template:(Log_event.get_message_template event)
      ~rendered_message:(Log_event.get_rendered_message event)
      ~properties:new_props
      ?exception_info:(Log_event.get_exception event)
      ()
  in

  let enriched_logger = Logger.with_enricher logger enricher in

  Logger.information enriched_logger "Enriched message" [];

  List.iter (fun s -> s.Composite_sink.flush_fn ()) [sink];
  List.iter (fun s -> s.Composite_sink.close_fn ()) [sink];

  let content = read_file path in

  check bool "Enriched message logged" true
    (contains "Enriched message" content);
  check bool "CorrelationId in output" true (contains "corr-456" content);

  Sys.remove path
;;

let test_logger_template_rendering () =
  let path = temp_file () in
  let sink = create_file_sink_fn path in
  let logger = Logger.create ~min_level:Level.Information ~sinks:[sink] in

  (* Log with template variables - these should be expanded in rendered
     output *)
  Logger.information logger "User {username} logged in from {ip_address}"
    [("username", `String "alice"); ("ip_address", `String "192.168.1.1")];

  (* Log with multiple variable types *)
  Logger.information logger "Processing {count} items for user {user_id}"
    [("count", `Int 42); ("user_id", `Int 123)];

  List.iter (fun s -> s.Composite_sink.flush_fn ()) [sink];
  List.iter (fun s -> s.Composite_sink.close_fn ()) [sink];

  let content = read_file path in

  (* Verify template variables are expanded in the output *)
  check bool "Username expanded" true
    (contains "User alice logged in from 192.168.1.1" content);
  check bool "IP address expanded" true (contains "192.168.1.1" content);
  check bool "Count expanded" true
    (contains "Processing 42 items for user 123" content);
  check bool "User ID expanded" true (contains "user 123" content);

  (* Verify raw template placeholders are NOT in the output *)
  check bool "Raw {username} not in output" false
    (contains "{username}" content);
  check bool "Raw {ip_address} not in output" false
    (contains "{ip_address}" content);
  check bool "Raw {count} not in output" false (contains "{count}" content);
  check bool "Raw {user_id} not in output" false (contains "{user_id}" content);

  Sys.remove path
;;

let () =
  run "Logger Tests"
    [ ( "level_filtering"
      , [ test_case "Level filtering works correctly" `Quick
            test_logger_level_filtering
        ; test_case "is_enabled returns correct values" `Quick
            test_logger_is_enabled ] )
    ; ( "context"
      , [ test_case "Context properties added to events" `Quick
            test_logger_context ] )
    ; ( "exceptions"
      , [ test_case "Exceptions can be logged" `Quick
            test_logger_write_with_exception ] )
    ; ( "sinks"
      , [ test_case "Multiple sinks receive events" `Quick
            test_logger_multiple_sinks ] )
    ; ( "filters"
      , [ test_case "Additional filters can be added" `Quick
            test_logger_add_min_level_filter ] )
    ; ( "enrichment"
      , [test_case "Enrichers modify events" `Quick test_logger_enricher] )
    ; ( "template_rendering"
      , [ test_case "Template variables are expanded in output" `Quick
            test_logger_template_rendering ] ) ]
;;
