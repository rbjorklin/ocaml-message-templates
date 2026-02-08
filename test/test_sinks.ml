(** Tests for sink implementations *)

open Alcotest
open Message_templates

(** Helper to check if string contains substring *)
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

let temp_file () = Filename.temp_file "test_sink_" ".log"

let create_test_event ?(level = Level.Information) message =
  Log_event.create ~level ~message_template:message ~rendered_message:message
    ~properties:[] ()
;;

let test_null_sink () =
  let sink = Null_sink.create () in
  let event = create_test_event "Test message" in
  (* Just verify these don't throw exceptions *)
  Null_sink.emit sink event;
  Null_sink.flush sink;
  Null_sink.close sink;
  check bool "Null sink handled events" true true
;;

let test_file_sink_basic () =
  let path = temp_file () in
  let sink = File_sink.create path in
  let event1 = create_test_event ~level:Level.Information "First message" in
  let event2 = create_test_event ~level:Level.Warning "Second message" in

  File_sink.emit sink event1;
  File_sink.emit sink event2;
  File_sink.flush sink;
  File_sink.close sink;

  (* Verify file was created and contains content *)
  let content =
    let ic = open_in path in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic; s
  in

  check bool "File contains first message" true
    (contains "First message" content);
  check bool "File contains second message" true
    (contains "Second message" content);
  check bool "File contains INF" true (contains "INF" content);
  check bool "File contains WRN" true (contains "WRN" content);

  (* Cleanup *)
  Sys.remove path
;;

let test_file_sink_rolling () =
  (* This is a basic test - we can't easily test actual rolling without waiting
     for time to pass, but we can test that the sink accepts the rolling
     parameter *)
  let path = temp_file () in
  let sink_daily = File_sink.create ~rolling:File_sink.Daily path in
  let sink_hourly = File_sink.create ~rolling:File_sink.Hourly path in

  let event = create_test_event "Rolling test" in

  (* Emit to both sinks *)
  File_sink.emit sink_daily event;
  File_sink.emit sink_hourly event;

  File_sink.close sink_daily;
  File_sink.close sink_hourly;

  (* Cleanup *)
  ( try Sys.remove path with _ -> () );
  (* Also try to cleanup any rolled files *)
  let dir = Filename.dirname path in
  let base = Filename.basename path in
  let pattern = Filename.remove_extension base in
  let files = Sys.readdir dir in
  Array.iter
    (fun f ->
      if String.starts_with ~prefix:pattern f then
        try
          Sys.remove (Filename.concat dir f)
        with _ -> () )
    files;

  check bool "Rolling sinks created successfully" true true
;;

let test_composite_sink () =
  let path1 = temp_file () in
  let path2 = temp_file () in

  let file_sink1 = File_sink.create path1 in
  let file_sink2 = File_sink.create path2 in

  let sink1 =
    { Composite_sink.emit_fn= (fun event -> File_sink.emit file_sink1 event)
    ; flush_fn= (fun () -> File_sink.flush file_sink1)
    ; close_fn= (fun () -> File_sink.close file_sink1)
    ; min_level= None }
  in

  let sink2 =
    { Composite_sink.emit_fn= (fun event -> File_sink.emit file_sink2 event)
    ; flush_fn= (fun () -> File_sink.flush file_sink2)
    ; close_fn= (fun () -> File_sink.close file_sink2)
    ; min_level= None }
  in

  let composite = Composite_sink.create [sink1; sink2] in

  let event = create_test_event "Composite test message" in
  Composite_sink.emit composite event;
  Composite_sink.flush composite;
  Composite_sink.close composite;

  (* Verify both files contain the message *)
  let read_file path =
    let ic = open_in path in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic; s
  in

  let content1 = read_file path1 in
  let content2 = read_file path2 in

  check bool "Sink 1 contains message" true
    (contains "Composite test message" content1);
  check bool "Sink 2 contains message" true
    (contains "Composite test message" content2);

  (* Cleanup *)
  Sys.remove path1;
  Sys.remove path2
;;

let test_console_sink () =
  (* Console sink is hard to test automatically, but we can at least verify it
     doesn't throw exceptions *)
  let sink = Console_sink.create () in
  let event = create_test_event "Console test" in

  (* These should not raise exceptions *)
  Console_sink.emit sink event;
  Console_sink.flush sink;
  Console_sink.close sink;

  check bool "Console sink handled events" true true
;;

let test_console_sink_with_colors () =
  let sink = Console_sink.create ~colors:true () in
  let event = create_test_event ~level:Level.Error "Error message" in

  (* Should not throw exception even with colors *)
  Console_sink.emit sink event;
  Console_sink.close sink;

  check bool "Console sink with colors handled events" true true
;;

let () =
  run "Sink Tests"
    [ ( "null_sink"
      , [test_case "Null sink basic operations" `Quick test_null_sink] )
    ; ( "file_sink"
      , [ test_case "File sink basic operations" `Quick test_file_sink_basic
        ; test_case "File sink rolling configuration" `Quick
            test_file_sink_rolling ] )
    ; ( "composite_sink"
      , [ test_case "Composite sink routes to multiple sinks" `Quick
            test_composite_sink ] )
    ; ( "console_sink"
      , [ test_case "Console sink basic operations" `Quick test_console_sink
        ; test_case "Console sink with colors" `Quick
            test_console_sink_with_colors ] ) ]
;;
