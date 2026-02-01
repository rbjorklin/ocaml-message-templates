(** Message Templates - Lwt Async Support

    This package provides async logging support for the message-templates
    library using Lwt for non-blocking I/O operations.

    Example usage:
    {[
      open Message_templates
      open Message_templates_lwt

      let setup_logging () =
        Configuration.create ()
        |> Configuration.minimum_level Level.Information
        |> Configuration.write_to_console ~colors:true ()
        |> Configuration.write_to_file ~rolling:Daily "app.log"
        |> Configuration.create_logger
      ;;

      let main () =
        let logger = setup_logging () in
        let* () = Lwt_logger.information logger "Server starting" [] in
        (* your async code here *)
        Lwt.return ()
      ;;

      let () = Lwt_main.run (main ())
    ]} *)

(** Lwt sink interface and utilities *)
module Lwt_sink = Lwt_sink

(** Lwt file sink with rolling support *)
module Lwt_file_sink = Lwt_file_sink

(** Lwt console sink for stdout/stderr output *)
module Lwt_console_sink = Lwt_console_sink

(** Lwt logger implementation *)
module Lwt_logger = Lwt_logger

(** Lwt configuration builder *)
module Configuration = Lwt_configuration
