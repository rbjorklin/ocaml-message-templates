(** Basic tests for message-templates-lwt *)

open Message_templates
open Message_templates_lwt
open Lwt.Syntax

(* These async test functions are wrapped by test_lwt_logger_sync and
   test_lwt_console_sink_sync below *)
let _test_lwt_logger () =
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Debug
    |> Configuration.write_to_console ()
    |> Configuration.create_logger
  in
  let* () = Lwt_logger.information logger "Test message" [] in
  let* () = Lwt_logger.debug logger "Debug message" [] in
  Lwt.return ()
;;

let _test_lwt_console_sink () =
  let sink = Lwt_console_sink.create ~colors:true () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test {name}"
      ~rendered_message:"Test message"
      ~properties:[("name", `String "test")]
      ()
  in
  let* () = Lwt_console_sink.emit sink event in
  Lwt.return ()
;;

let test_lwt_logger_sync () =
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Debug
    |> Configuration.write_to_console ()
    |> Configuration.create_logger
  in
  Lwt_main.run (Lwt_logger.information logger "Test message" []);
  ()
;;

let test_lwt_console_sink_sync () =
  let sink = Lwt_console_sink.create ~colors:true () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test {name}"
      ~rendered_message:"Test message"
      ~properties:[("name", `String "test")]
      ()
  in
  Lwt_main.run (Lwt_console_sink.emit sink event);
  ()
;;

let () =
  let open Alcotest in
  run "Lwt Tests"
    [ ("logger", [test_case "Basic Lwt logger" `Quick test_lwt_logger_sync])
    ; ("sinks", [test_case "Lwt console sink" `Quick test_lwt_console_sink_sync])
    ]
;;
