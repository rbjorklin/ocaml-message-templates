(** Basic tests for message-templates-eio *)

open Message_templates
open Message_templates_eio

let test_eio_logger () =
  Eio.Switch.run
  @@ fun sw ->
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Debug
    |> Configuration.write_to_console ()
    |> Configuration.create_logger ~sw
  in
  Eio_logger.information logger "Test message" [];
  Eio_logger.debug logger "Debug message" []
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
    [ ("logger", [test_case "Basic Eio logger" `Quick test_eio_logger])
    ; ("sinks", [test_case "Eio console sink" `Quick test_eio_console_sink]) ]
;;
