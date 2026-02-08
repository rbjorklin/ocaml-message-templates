(** Eio logger - sync logger implementation for Eio fibers using Logger_core *)

open Message_templates

(** Eio uses direct style (like sync), so we use Identity monad *)
module Eio_monad = Logger_core.Identity

(** Sink function adapter for Eio *)
module Eio_sink_fn = struct
  type sink = Eio_sink.sink_fn

  let emit_fn sink event =
    sink.Eio_sink.emit_fn event;
    ()
  ;;

  let flush_fn sink = sink.Eio_sink.flush_fn (); ()

  let close_fn sink = sink.Eio_sink.close_fn (); ()
end

(** Instantiate the logger core with Identity monad *)
module Eio_logger_core = Logger_core.Make (Eio_monad) (Eio_sink_fn)

(** Logger type with optional switch for async operations *)
type t =
  { core: Eio_logger_core.t
  ; sw: Eio.Switch.t option }

(** Create a logger *)
let create ?sw ~min_level ~sinks () =
  {core= Eio_logger_core.create ~min_level ~sinks; sw}
;;

(** Write a log event - synchronous *)
let write t ?exn level message properties =
  ignore (Eio_logger_core.write t.core ?exn level message properties)
;;

(** Fire-and-forget logging - runs in background fiber *)
let write_async t ?exn level message properties =
  match t.sw with
  | Some sw ->
      Eio.Fiber.fork ~sw (fun () ->
          try write t ?exn level message properties
          with exn ->
            Printf.eprintf "Logging error: %s\n" (Printexc.to_string exn) )
  | None -> write t ?exn level message properties
;;

(** Check if a level is enabled *)
let is_enabled t = Eio_logger_core.is_enabled t.core

(** Level-specific convenience methods - synchronous *)
let verbose t ?exn message properties =
  ignore (Eio_logger_core.verbose t.core ?exn message properties)
;;

let debug t ?exn message properties =
  ignore (Eio_logger_core.debug t.core ?exn message properties)
;;

let information t ?exn message properties =
  ignore (Eio_logger_core.information t.core ?exn message properties)
;;

let warning t ?exn message properties =
  ignore (Eio_logger_core.warning t.core ?exn message properties)
;;

let error t ?exn message properties =
  ignore (Eio_logger_core.error t.core ?exn message properties)
;;

let fatal t ?exn message properties =
  ignore (Eio_logger_core.fatal t.core ?exn message properties)
;;

(** Async level-specific convenience methods *)
let verbose_async t ?exn message properties =
  write_async t ?exn Level.Verbose message properties
;;

let debug_async t ?exn message properties =
  write_async t ?exn Level.Debug message properties
;;

let information_async t ?exn message properties =
  write_async t ?exn Level.Information message properties
;;

let warning_async t ?exn message properties =
  write_async t ?exn Level.Warning message properties
;;

let error_async t ?exn message properties =
  write_async t ?exn Level.Error message properties
;;

let fatal_async t ?exn message properties =
  write_async t ?exn Level.Fatal message properties
;;

(** Context and enrichment *)
let for_context t name value =
  {t with core= Eio_logger_core.for_context t.core name value}
;;

let with_enricher t enricher =
  {t with core= Eio_logger_core.with_enricher t.core enricher}
;;

let for_source t source = {t with core= Eio_logger_core.for_source t.core source}

(** Filters *)
let add_filter t filter = {t with core= Eio_logger_core.add_filter t.core filter}

let add_min_level_filter t level =
  {t with core= Eio_logger_core.add_min_level_filter t.core level}
;;

(** Flush all sinks *)
let flush t = ignore (Eio_logger_core.flush t.core)

(** Close all sinks *)
let close t = ignore (Eio_logger_core.close t.core)
