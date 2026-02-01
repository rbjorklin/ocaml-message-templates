(** Comprehensive tests for Json_sink module *)

open Alcotest
open Message_templates

let temp_file = Filename.temp_file "json_sink_test_" ".json"

let cleanup () =
  if Sys.file_exists temp_file then
    Sys.remove temp_file
;;

(** Helper to read all lines from file *)
let read_lines path =
  let ic = open_in path in
  let rec read_all acc =
    try
      let line = input_line ic in
      read_all (line :: acc)
    with End_of_file -> close_in ic; List.rev acc
  in
  read_all []
;;

(** Helper to parse JSON line *)
let parse_json_line line =
  match Yojson.Safe.from_string line with
  | json -> Ok json
  | exception ex -> Error (Printexc.to_string ex)
;;

let test_json_sink_basic () =
  cleanup ();
  let sink = Json_sink.create temp_file in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test message"
      ~rendered_message:"Test message" ~properties:[] ()
  in
  Json_sink.emit sink event;
  Json_sink.flush sink;
  Json_sink.close sink;

  let lines = read_lines temp_file in
  check int "Single event produces one line" 1 (List.length lines);

  ( match parse_json_line (List.hd lines) with
  | Ok json -> (
    match json with
    | `Assoc fields ->
        check bool "Has @t field" true (List.mem_assoc "@t" fields);
        check bool "Has @mt field" true (List.mem_assoc "@mt" fields);
        check bool "Has @m field" true (List.mem_assoc "@m" fields);
        check bool "Has @l field" true (List.mem_assoc "@l" fields)
    | _ -> fail "JSON should be an object" )
  | Error msg -> fail msg );
  cleanup ()
;;

let test_json_sink_clef_format () =
  cleanup ();
  let sink = Json_sink.create temp_file in
  let timestamp = Ptime.of_float_s 1706740800.0 |> Option.get in
  let event =
    Log_event.create ~timestamp ~level:Level.Warning
      ~message_template:"User {username} logged in"
      ~rendered_message:"User alice logged in"
      ~properties:[("username", `String "alice")]
      ()
  in
  Json_sink.emit sink event;
  Json_sink.close sink;

  let lines = read_lines temp_file in
  ( match parse_json_line (List.hd lines) with
  | Ok json -> (
    match json with
    | `Assoc fields -> (
        ( match List.assoc_opt "@t" fields with
        | Some (`String ts) ->
            (* Verify RFC3339 format *)
            check bool "Timestamp is valid RFC3339" true
              (String.contains ts 'T')
        | _ -> fail "@t should be a string" );

        ( match List.assoc_opt "@mt" fields with
        | Some (`String mt) ->
            check string "Message template preserved"
              "User {username} logged in" mt
        | _ -> fail "@mt should be a string" );

        ( match List.assoc_opt "@m" fields with
        | Some (`String m) ->
            check string "Rendered message correct" "User alice logged in" m
        | _ -> fail "@m should be a string" );

        match List.assoc_opt "@l" fields with
        | Some (`String l) -> check string "Level is Warning" "Warning" l
        | _ -> fail "@l should be a string" )
    | _ -> fail "JSON should be an object" )
  | Error msg -> fail msg );
  cleanup ()
;;

let test_json_sink_properties () =
  cleanup ();
  let sink = Json_sink.create temp_file in
  let properties =
    [ ("string_prop", `String "hello")
    ; ("int_prop", `Int 42)
    ; ("float_prop", `Float 3.14)
    ; ("bool_prop", `Bool true)
    ; ("null_prop", `Null)
    ; ("list_prop", `List [`Int 1; `Int 2; `Int 3])
    ; ("nested_obj", `Assoc [("key", `String "value")]) ]
  in
  let event =
    Log_event.create ~level:Level.Information
      ~message_template:"Test with properties"
      ~rendered_message:"Test with properties" ~properties ()
  in
  Json_sink.emit sink event;
  Json_sink.close sink;

  let lines = read_lines temp_file in
  ( match parse_json_line (List.hd lines) with
  | Ok json -> (
    match json with
    | `Assoc fields -> (
        check bool "Has string_prop" true (List.mem_assoc "string_prop" fields);
        check bool "Has int_prop" true (List.mem_assoc "int_prop" fields);
        check bool "Has float_prop" true (List.mem_assoc "float_prop" fields);
        check bool "Has bool_prop" true (List.mem_assoc "bool_prop" fields);
        check bool "Has null_prop" true (List.mem_assoc "null_prop" fields);
        check bool "Has list_prop" true (List.mem_assoc "list_prop" fields);
        check bool "Has nested_obj" true (List.mem_assoc "nested_obj" fields);

        ( match List.assoc_opt "string_prop" fields with
        | Some (`String s) -> check string "String prop correct" "hello" s
        | _ -> fail "string_prop should be a string" );

        match List.assoc_opt "int_prop" fields with
        | Some (`Int i) -> check int "Int prop correct" 42 i
        | _ -> fail "int_prop should be an int" )
    | _ -> fail "JSON should be an object" )
  | Error msg -> fail msg );
  cleanup ()
;;

let test_json_sink_multiple_events () =
  cleanup ();
  let sink = Json_sink.create temp_file in

  for i = 1 to 5 do
    let event =
      Log_event.create ~level:Level.Information
        ~message_template:(Printf.sprintf "Event %d" i)
        ~rendered_message:(Printf.sprintf "Event %d" i)
        ~properties:[("index", `Int i)]
        ()
    in
    Json_sink.emit sink event
  done;

  Json_sink.close sink;

  let lines = read_lines temp_file in
  check int "Five events produce five lines" 5 (List.length lines);

  List.iteri
    (fun i line ->
      match parse_json_line line with
      | Ok json -> (
        match json with
        | `Assoc fields -> (
          match List.assoc_opt "index" fields with
          | Some (`Int idx) ->
              check int (Printf.sprintf "Event %d index" (i + 1)) (i + 1) idx
          | _ -> fail "index should be an int" )
        | _ -> fail "Each line should be a JSON object" )
      | Error msg -> fail msg )
    lines;
  cleanup ()
;;

let test_json_sink_special_characters () =
  cleanup ();
  let sink = Json_sink.create temp_file in
  let event =
    Log_event.create ~level:Level.Information
      ~message_template:"Special chars: {value}"
      ~rendered_message:"Special chars: hello\nworld\t\"quoted\""
      ~properties:[("value", `String "hello\nworld\t\"quoted\"")]
      ()
  in
  Json_sink.emit sink event;
  Json_sink.close sink;

  let lines = read_lines temp_file in
  ( match parse_json_line (List.hd lines) with
  | Ok json -> (
    match json with
    | `Assoc fields -> (
      match List.assoc_opt "value" fields with
      | Some (`String s) ->
          check string "Special chars preserved" "hello\nworld\t\"quoted\"" s
      | _ -> fail "value should be a string" )
    | _ -> fail "JSON should be an object" )
  | Error msg -> fail msg );
  cleanup ()
;;

let test_json_sink_flush_close () =
  cleanup ();
  let sink = Json_sink.create temp_file in

  (* Write without flushing *)
  let event1 =
    Log_event.create ~level:Level.Information ~message_template:"Event 1"
      ~rendered_message:"Event 1" ~properties:[] ()
  in
  Json_sink.emit sink event1;

  (* Flush and verify data is written *)
  Json_sink.flush sink;
  let lines_after_flush = read_lines temp_file in
  check int "Data flushed to file" 1 (List.length lines_after_flush);

  (* Write another event *)
  let event2 =
    Log_event.create ~level:Level.Information ~message_template:"Event 2"
      ~rendered_message:"Event 2" ~properties:[] ()
  in
  Json_sink.emit sink event2;
  Json_sink.close sink;

  (* Verify both events are present after close *)
  let lines_after_close = read_lines temp_file in
  check int "Both events in file after close" 2 (List.length lines_after_close);
  cleanup ()
;;

let test_json_sink_of_out_channel () =
  cleanup ();
  let oc = open_out temp_file in
  let sink = Json_sink.of_out_channel oc in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  Json_sink.emit sink event;
  Json_sink.close sink;

  let lines = read_lines temp_file in
  check int "Event written via custom channel" 1 (List.length lines);
  cleanup ()
;;

let test_json_sink_level_variants () =
  cleanup ();
  let sink = Json_sink.create temp_file in
  let levels =
    [ (Level.Verbose, "Verbose")
    ; (Level.Debug, "Debug")
    ; (Level.Information, "Information")
    ; (Level.Warning, "Warning")
    ; (Level.Error, "Error")
    ; (Level.Fatal, "Fatal") ]
  in

  List.iter
    (fun (level, _level_name) ->
      let event =
        Log_event.create ~level ~message_template:"Test"
          ~rendered_message:"Test" ~properties:[] ()
      in
      Json_sink.emit sink event )
    levels;

  Json_sink.close sink;

  let lines = read_lines temp_file in
  check int "All six levels written" 6 (List.length lines);

  List.iteri
    (fun i line ->
      let expected_level = snd (List.nth levels i) in
      match parse_json_line line with
      | Ok json -> (
        match json with
        | `Assoc fields -> (
          match List.assoc_opt "@l" fields with
          | Some (`String l) ->
              check string (Printf.sprintf "Level %d" i) expected_level l
          | _ -> fail "@l should be a string" )
        | _ -> fail "JSON should be an object" )
      | Error msg -> fail msg )
    lines;
  cleanup ()
;;

let test_json_sink_append_mode () =
  cleanup ();

  (* First sink - write initial events *)
  let sink1 = Json_sink.create temp_file in
  let event1 =
    Log_event.create ~level:Level.Information ~message_template:"First"
      ~rendered_message:"First" ~properties:[] ()
  in
  Json_sink.emit sink1 event1;
  Json_sink.close sink1;

  (* Second sink - should append *)
  let sink2 = Json_sink.create temp_file in
  let event2 =
    Log_event.create ~level:Level.Information ~message_template:"Second"
      ~rendered_message:"Second" ~properties:[] ()
  in
  Json_sink.emit sink2 event2;
  Json_sink.close sink2;

  let lines = read_lines temp_file in
  check int "Both events present after append" 2 (List.length lines);

  ( match parse_json_line (List.hd lines) with
  | Ok json -> (
    match json with
    | `Assoc fields -> (
      match List.assoc_opt "@mt" fields with
      | Some (`String mt) -> check string "First event preserved" "First" mt
      | _ -> fail "@mt should be a string" )
    | _ -> fail "JSON should be an object" )
  | Error msg -> fail msg );
  cleanup ()
;;

let () =
  run "Json_sink Tests"
    [ ( "basic"
      , [ test_case "Basic event" `Quick test_json_sink_basic
        ; test_case "CLEF format" `Quick test_json_sink_clef_format
        ; test_case "Properties" `Quick test_json_sink_properties
        ; test_case "Multiple events" `Quick test_json_sink_multiple_events
        ; test_case "Special characters" `Quick
            test_json_sink_special_characters
        ; test_case "Flush and close" `Quick test_json_sink_flush_close
        ; test_case "Custom channel" `Quick test_json_sink_of_out_channel
        ; test_case "All level variants" `Quick test_json_sink_level_variants
        ; test_case "Append mode" `Quick test_json_sink_append_mode ] ) ]
;;
