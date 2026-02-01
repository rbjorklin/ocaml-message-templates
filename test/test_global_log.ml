(** Tests for Log and LogContext modules *)

open Alcotest
open Message_templates

let temp_file () =
  Filename.temp_file "test_global_log_" ".log"

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

let create_logger path =
  Configuration.create ()
  |> Configuration.minimum_level Level.Information
  |> Configuration.write_to_file path
  |> Configuration.create_logger

let test_log_set_and_get () =
  let path = temp_file () in
  let logger = create_logger path in
  
  (* Set the global logger *)
  Log.set_logger logger;
  
  (* Get should return Some *)
  check bool "Logger is set" true (Option.is_some (Log.get_logger ()));
  
  Log.close_and_flush ();
  Sys.remove path

let test_log_level_methods () =
  let path = temp_file () in
  let logger = create_logger path in
  Log.set_logger logger;
  
  (* Log at different levels *)
  Log.information "Info message" [];
  Log.warning "Warning message" [];
  Log.error "Error message" [];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Info logged" true (contains "Info message" content);
  check bool "Warning logged" true (contains "Warning message" content);
  check bool "Error logged" true (contains "Error message" content);
  
  Sys.remove path

let test_log_level_filtering () =
  let path = temp_file () in
  (* Create logger with Warning minimum level *)
  let logger = 
    Configuration.create ()
    |> Configuration.warning
    |> Configuration.write_to_file path
    |> Configuration.create_logger
  in
  Log.set_logger logger;
  
  (* These should NOT be logged *)
  Log.debug "Debug message" [];
  Log.information "Info message" [];
  
  (* These SHOULD be logged *)
  Log.warning "Warning message" [];
  Log.error "Error message" [];
  
  Log.close_and_flush ();
  
  let content = read_file path in
  
  check bool "Debug not logged" false (contains "Debug message" content);
  check bool "Info not logged" false (contains "Info message" content);
  check bool "Warning logged" true (contains "Warning message" content);
  check bool "Error logged" true (contains "Error message" content);
  
  Sys.remove path

let test_log_is_enabled () =
  let path = temp_file () in
  let logger = create_logger path in
  Log.set_logger logger;
  
  (* Check level enablement - logger min_level is Information *)
  check bool "Debug not enabled" false (Log.is_enabled Level.Debug);
  check bool "Info enabled" true (Log.is_enabled Level.Information);
  check bool "Warning enabled" true (Log.is_enabled Level.Warning);
  
  Log.close_and_flush ();
  Sys.remove path

let test_log_no_logger_configured () =
  (* Ensure no logger is set *)
  Log.close_and_flush ();
  
  (* These should not throw even without a logger *)
  Log.information "No logger message" [];
  Log.warning "Another no logger message" [];
  Log.error "Error without logger" [];
  
  (* is_enabled should return false *)
  check bool "is_enabled returns false" false (Log.is_enabled Level.Information);
  
  check bool "No logger handled gracefully" true true

let test_log_context_push_pop () =
  (* Clear any existing context *)
  Log_context.clear ();
  
  (* Push some properties *)
  Log_context.push_property "RequestId" (`String "req-123");
  Log_context.push_property "UserId" (`String "user-456");
  
  let props = Log_context.current_properties () in
  
  check bool "RequestId in context" true (List.mem_assoc "RequestId" props);
  check bool "UserId in context" true (List.mem_assoc "UserId" props);
  
  (* Pop one property *)
  Log_context.pop_property ();
  let props_after_pop = Log_context.current_properties () in
  
  check bool "UserId popped" false (List.mem_assoc "UserId" props_after_pop);
  check bool "RequestId still present" true (List.mem_assoc "RequestId" props_after_pop);
  
  (* Clear all *)
  Log_context.clear ();
  check bool "Context cleared" true (Log_context.current_properties () = [])

let test_log_context_with_property () =
  Log_context.clear ();
  
  let result = Log_context.with_property "CorrelationId" (`String "corr-789") (fun () ->
    let props = Log_context.current_properties () in
    List.mem_assoc "CorrelationId" props
  ) in
  
  check bool "Property was in context during execution" true result;
  
  (* Property should be auto-popped *)
  check bool "Property auto-popped" false (List.mem_assoc "CorrelationId" (Log_context.current_properties ()));
  
  Log_context.clear ()

let test_log_context_with_exception () =
  Log_context.clear ();
  
  Log_context.push_property "TestProp" (`String "test");
  
  (* Function that raises an exception *)
  let exception_raised = ref false in
  try
    Log_context.with_property "TempProp" (`String "temp") (fun () ->
      raise (Failure "Test exception")
    )
  with Failure _ ->
    exception_raised := true
  ;
  
  check bool "Exception was raised" true !exception_raised;
  
  (* Original property should still be there *)
  check bool "Original property preserved" true (List.mem_assoc "TestProp" (Log_context.current_properties ()));
  
  (* Temp property should be popped even with exception *)
  check bool "Temp property popped" false (List.mem_assoc "TempProp" (Log_context.current_properties ()));
  
  Log_context.clear ()

let test_log_context_with_scope () =
  Log_context.clear ();
  
  Log_context.push_property "OuterProp" (`String "outer");
  
  let result = Log_context.with_scope (fun () ->
    Log_context.push_property "InnerProp" (`String "inner");
    let inner_props = Log_context.current_properties () in
    (* Should have both properties *)
    List.mem_assoc "OuterProp" inner_props && List.mem_assoc "InnerProp" inner_props
  ) in
  
  check bool "Both properties visible inside scope" true result;
  
  (* After scope, should only have OuterProp *)
  let outer_props = Log_context.current_properties () in
  check bool "OuterProp preserved" true (List.mem_assoc "OuterProp" outer_props);
  check bool "InnerProp removed by scope" false (List.mem_assoc "InnerProp" outer_props);
  
  Log_context.clear ()

let test_log_context_with_properties () =
  Log_context.clear ();
  
  let props = [
    ("Prop1", `String "value1");
    ("Prop2", `String "value2");
    ("Prop3", `String "value3");
  ] in
  
  let result = Log_context.with_properties props (fun () ->
    let current = Log_context.current_properties () in
    List.mem_assoc "Prop1" current &&
    List.mem_assoc "Prop2" current &&
    List.mem_assoc "Prop3" current
  ) in
  
  check bool "All properties in context" true result;
  
  (* All should be popped *)
  check bool "All properties popped" true (Log_context.current_properties () = []);
  
  Log_context.clear ()

let test_log_close_and_flush () =
  let path = temp_file () in
  let logger = create_logger path in
  Log.set_logger logger;
  
  Log.information "Before close" [];
  
  (* Close and flush *)
  Log.close_and_flush ();
  
  (* Logger should be None after close *)
  check bool "Logger cleared" true (Log.get_logger () = None);
  
  let content = read_file path in
  check bool "Message was flushed" true (contains "Before close" content);
  
  Sys.remove path

let () =
  run "Global Log Tests" [
    "basic", [
      test_case "Log set_logger and get_logger" `Quick test_log_set_and_get;
      test_case "Log level methods" `Quick test_log_level_methods;
      test_case "Log level filtering" `Quick test_log_level_filtering;
      test_case "Log is_enabled" `Quick test_log_is_enabled;
      test_case "Log handles no logger gracefully" `Quick test_log_no_logger_configured;
      test_case "Log close_and_flush" `Quick test_log_close_and_flush;
    ];
    "context", [
      test_case "Context push and pop" `Quick test_log_context_push_pop;
      test_case "Context with_property auto-pops" `Quick test_log_context_with_property;
      test_case "Context handles exceptions" `Quick test_log_context_with_exception;
      test_case "Context with_scope preserves outer context" `Quick test_log_context_with_scope;
      test_case "Context with_properties multiple" `Quick test_log_context_with_properties;
    ];
  ]
