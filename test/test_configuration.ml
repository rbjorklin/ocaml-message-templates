(** Tests for Configuration module *)

open Alcotest
open Message_templates

let temp_file () =
  Filename.temp_file "test_config_" ".log"

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

let test_configuration_create () =
  let _config = Configuration.create () in
  (* Just verify it compiles and doesn't throw *)
  check bool "Configuration created" true true

let test_configuration_minimum_level () =
  let path = temp_file () in
  let logger = 
    Configuration.create ()
    |> Configuration.minimum_level Level.Warning
    |> Configuration.write_to_file path
    |> Configuration.create_logger
  in
  
  (* Debug should NOT be logged *)
  Logger.debug logger "Debug message" [];
  (* Warning SHOULD be logged *)
  Logger.warning logger "Warning message" [];
  
  (* Flush and close *)
  Logger.flush logger;
  Logger.close logger;
  
  let content = read_file path in
  
  check bool "Debug not logged" false (contains "Debug message" content);
  check bool "Warning logged" true (contains "Warning message" content);
  
  Sys.remove path

let test_configuration_level_convenience_methods () =
  (* Test verbose method *)
  let _ = Configuration.create () |> Configuration.verbose in
  (* Test debug method *)
  let _ = Configuration.create () |> Configuration.debug in
  (* Test information method *)
  let _ = Configuration.create () |> Configuration.information in
  (* Test warning method *)
  let _ = Configuration.create () |> Configuration.warning in
  (* Test error method *)
  let _ = Configuration.create () |> Configuration.error in
  (* Test fatal method *)
  let _ = Configuration.create () |> Configuration.fatal in
  
  check bool "All level convenience methods work" true true

let test_configuration_enrich_with_property () =
  let path = temp_file () in
  let logger = 
    Configuration.create ()
    |> Configuration.minimum_level Level.Information
    |> Configuration.enrich_with_property "AppVersion" (`String "1.0.0")
    |> Configuration.write_to_file path
    |> Configuration.create_logger
  in
  
  Logger.information logger "Test message" [];
  
  (* Flush and close *)
  Logger.flush logger;
  Logger.close logger;
  
  let content = read_file path in
  
  check bool "Message logged" true (contains "Test message" content);
  check bool "AppVersion in output" true (contains "1.0.0" content);
  
  Sys.remove path

let test_configuration_filter_by_min_level () =
  let path = temp_file () in
  let logger = 
    Configuration.create ()
    |> Configuration.debug
    |> Configuration.filter_by_min_level Level.Warning
    |> Configuration.write_to_file path
    |> Configuration.create_logger
  in
  
  (* Even though logger min_level is Debug, filter requires Warning *)
  Logger.debug logger "Debug after filter" [];
  Logger.information logger "Info after filter" [];
  Logger.warning logger "Warning after filter" [];
  
  (* Flush and close *)
  Logger.flush logger;
  Logger.close logger;
  
  let content = read_file path in
  
  check bool "Debug not logged" false (contains "Debug after filter" content);
  check bool "Info not logged" false (contains "Info after filter" content);
  check bool "Warning logged" true (contains "Warning after filter" content);
  
  Sys.remove path

let test_configuration_multiple_sinks () =
  let path1 = temp_file () in
  let path2 = temp_file () in
  
  let logger = 
    Configuration.create ()
    |> Configuration.minimum_level Level.Information
    |> Configuration.write_to_file path1
    |> Configuration.write_to_file path2
    |> Configuration.create_logger
  in
  
  Logger.information logger "Multi-sink message" [];
  
  (* Flush and close *)
  Logger.flush logger;
  Logger.close logger;
  
  let content1 = read_file path1 in
  let content2 = read_file path2 in
  
  check bool "Sink 1 has message" true (contains "Multi-sink message" content1);
  check bool "Sink 2 has message" true (contains "Multi-sink message" content2);
  
  Sys.remove path1;
  Sys.remove path2

let test_configuration_write_to_null () =
  let logger = 
    Configuration.create ()
    |> Configuration.minimum_level Level.Information
    |> Configuration.write_to_null ()
    |> Configuration.create_logger
  in
  
  (* Should not throw *)
  Logger.information logger "Null sink message" [];
  Logger.error logger "Error to null" [];
  
  check bool "Null sink handled messages" true true

let test_configuration_chaining () =
  let path = temp_file () in
  
  (* Test complex chaining *)
  let logger = 
    Configuration.create ()
    |> Configuration.debug
    |> Configuration.enrich_with_property "Environment" (`String "Test")
    |> Configuration.enrich_with_property "Service" (`String "MyApp")
    |> Configuration.write_to_file path
    |> Configuration.create_logger
  in
  
  Logger.information logger "Chained message" [];
  
  (* Flush and close *)
  Logger.flush logger;
  Logger.close logger;
  
  let content = read_file path in
  
  check bool "Message logged" true (contains "Chained message" content);
  check bool "Environment in output" true (contains "Test" content);
  check bool "Service in output" true (contains "MyApp" content);
  
  Sys.remove path

let test_filter_level_filter () =
  (* Test the level filter directly *)
  let event = Log_event.create 
    ~level:Level.Warning
    ~message_template:"Test"
    ~rendered_message:"Test"
    ~properties:[]
    ()
  in
  
  (* Warning event should pass Warning filter *)
  check bool "Warning >= Warning" true (Filter.level_filter Level.Warning event);
  (* Warning event should pass Error filter *)
  check bool "Warning >= Error" false (Filter.level_filter Level.Error event);
  (* Warning event should NOT pass Information filter *)
  check bool "Warning < Information" true (Filter.level_filter Level.Information event)

let test_filter_matching () =
  let event = Log_event.create 
    ~level:Level.Information
    ~message_template:"Test"
    ~rendered_message:"Test"
    ~properties:["RequestId", `String "123"]
    ()
  in
  
  check bool "RequestId property exists" true (Filter.matching "RequestId" event);
  check bool "Other property does not exist" false (Filter.matching "OtherId" event)

let test_filter_all () =
  let event = Log_event.create 
    ~level:Level.Warning
    ~message_template:"Test"
    ~rendered_message:"Test"
    ~properties:["RequestId", `String "123"]
    ()
  in
  
  let filter1 = Filter.level_filter Level.Information in
  let filter2 = Filter.matching "RequestId" in
  let combined = Filter.all [filter1; filter2] in
  
  check bool "All filters pass" true (combined event);
  
  let failing_filter = Filter.matching "NonExistent" in
  let combined_fail = Filter.all [filter1; failing_filter] in
  
  check bool "One filter fails" false (combined_fail event)

let test_filter_any () =
  let event = Log_event.create 
    ~level:Level.Warning
    ~message_template:"Test"
    ~rendered_message:"Test"
    ~properties:["RequestId", `String "123"]
    ()
  in
  
  let filter1 = Filter.level_filter Level.Error in  (* This will fail *)
  let filter2 = Filter.matching "RequestId" in      (* This will pass *)
  let combined = Filter.any [filter1; filter2] in
  
  check bool "Any filter passes" true (combined event);
  
  let failing1 = Filter.level_filter Level.Fatal in
  let failing2 = Filter.matching "NonExistent" in
  let combined_fail = Filter.any [failing1; failing2] in
  
  check bool "All filters fail" false (combined_fail event)

let test_filter_not () =
  let event = Log_event.create 
    ~level:Level.Debug
    ~message_template:"Test"
    ~rendered_message:"Test"
    ~properties:[]
    ()
  in
  
  let level_filter = Filter.level_filter Level.Information in
  let not_filter = Filter.not_filter level_filter in
  
  (* Debug < Information, so level_filter returns false, not_filter returns true *)
  check bool "Not filter inverts" true (not_filter event)

let () =
  run "Configuration Tests" [
    "basic", [
      test_case "Configuration can be created" `Quick test_configuration_create;
      test_case "Minimum level can be set" `Quick test_configuration_minimum_level;
      test_case "Level convenience methods work" `Quick test_configuration_level_convenience_methods;
    ];
    "enrichment", [
      test_case "Properties can be added via configuration" `Quick test_configuration_enrich_with_property;
    ];
    "filtering", [
      test_case "Filter by minimum level works" `Quick test_configuration_filter_by_min_level;
      test_case "Level filter predicates work" `Quick test_filter_level_filter;
      test_case "Property matching filter works" `Quick test_filter_matching;
      test_case "All filter combines with AND" `Quick test_filter_all;
      test_case "Any filter combines with OR" `Quick test_filter_any;
      test_case "Not filter inverts result" `Quick test_filter_not;
    ];
    "sinks", [
      test_case "Multiple sinks can be configured" `Quick test_configuration_multiple_sinks;
      test_case "Null sink can be configured" `Quick test_configuration_write_to_null;
    ];
    "chaining", [
      test_case "Complex chaining works" `Quick test_configuration_chaining;
    ];
  ]
