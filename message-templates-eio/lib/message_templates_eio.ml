(** Message Templates - Eio Async Support

    This package provides async logging support for the message-templates
    library using Eio for effects-based concurrency.

    Example usage:
    {[
      open Message_templates
      open Message_templates_eio

      let run ~stdout ~fs =
        Eio.Switch.run
        @@ fun sw ->
        let logger =
          Configuration.create ()
          |> Configuration.minimum_level Level.Information
          |> Configuration.write_to_console ~colors:true ()
          |> Configuration.write_to_file ~rolling:Daily "app.log"
          |> Configuration.create_logger ~sw
        in

        (* Synchronous logging - waits for completion *)
        Eio_logger.information logger "Server starting" [];

        (* Fire-and-forget logging - returns immediately *)
        Eio_logger.write_async logger "Background task started" [];

        (* your Eio code here *)
        ()
      ;;

      let () = Eio_main.run @@ fun env -> run ~stdout:env#stdout ~fs:env#fs
    ]} *)

(** Eio sink interface and utilities *)
module Eio_sink = Eio_sink

(** Eio file sink with rolling support *)
module Eio_file_sink = Eio_file_sink

(** Eio console sink for stdout/stderr output *)
module Eio_console_sink = Eio_console_sink

(** Eio logger implementation *)
module Eio_logger = Eio_logger

(** Eio configuration builder *)
module Configuration = Eio_configuration
