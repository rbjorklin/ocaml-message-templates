(** Lwt logger - async logger implementation using Logger_core *)

open Message_templates
open Lwt.Syntax

(** Lwt monad implementation *)
module Lwt_monad = struct
  type 'a t = 'a Lwt.t

  let return = Lwt.return

  let bind = Lwt.bind

  let iter_p = Lwt_list.iter_p
end

(** Sink function adapter for Lwt *)
module Lwt_sink_fn = struct
  type sink = Lwt_sink.sink_fn

  let emit_fn sink event = sink.Lwt_sink.emit_fn event

  let flush_fn sink = sink.Lwt_sink.flush_fn ()

  let close_fn sink = sink.Lwt_sink.close_fn ()
end

(** Instantiate the logger core with Lwt monad *)
module Lwt_logger_core = Logger_core.Make (Lwt_monad) (Lwt_sink_fn)

(** Logger type *)
type t = Lwt_logger_core.t

(** Create a logger *)
let create ~min_level ~sinks = Lwt_logger_core.create ~min_level ~sinks

(** Write a log event - returns Lwt promise *)
let write t ?exn level message properties =
  Lwt_logger_core.write t ?exn level message properties
;;

(** Check if a level is enabled *)
let is_enabled = Lwt_logger_core.is_enabled

(** Level-specific convenience methods *)
let verbose t ?exn message properties =
  Lwt_logger_core.verbose t ?exn message properties
;;

let debug t ?exn message properties =
  Lwt_logger_core.debug t ?exn message properties
;;

let information t ?exn message properties =
  Lwt_logger_core.information t ?exn message properties
;;

let warning t ?exn message properties =
  Lwt_logger_core.warning t ?exn message properties
;;

let error t ?exn message properties =
  Lwt_logger_core.error t ?exn message properties
;;

let fatal t ?exn message properties =
  Lwt_logger_core.fatal t ?exn message properties
;;

(** Context and enrichment *)
let for_context = Lwt_logger_core.for_context

let with_enricher = Lwt_logger_core.with_enricher

let for_source = Lwt_logger_core.for_source

(** Filters *)
let add_filter = Lwt_logger_core.add_filter

let add_min_level_filter = Lwt_logger_core.add_min_level_filter

(** Flush all sinks *)
let flush t = Lwt_logger_core.flush t

(** Close all sinks *)
let close t = Lwt_logger_core.close t
