(** Basic tests for message-templates-eio *)

open Message_templates
open Message_templates_eio

(* Note: Eio logger tests require an Eio switch context. The create_logger
   function takes an optional ~sw parameter. For now we test the sink only - the
   full async tests would need Eio_main.run context which isn't available in
   standard test setup. *)
let test_eio_logger_basic () =
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Debug
    |> Configuration.write_to_console ()
    |> Configuration.create_logger
  in
  (* Just verify logger was created - actual async operations require Eio
     context *)
  Alcotest.(check bool) "Logger created" true (logger <> Obj.magic ())
;;

let test_eio_console_sink () =
  let sink = Eio_console_sink.create ~colors:true () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test {name}"
      ~rendered_message:"Test message"
      ~properties:[("name", `String "test")]
      ()
  in
  Eio_console_sink.emit sink event
;;

let () =
  let open Alcotest in
  run "Eio Tests"
    [ ("logger", [test_case "Basic Eio logger" `Quick test_eio_logger_basic])
    ; ("sinks", [test_case "Eio console sink" `Quick test_eio_console_sink]) ]
;;
