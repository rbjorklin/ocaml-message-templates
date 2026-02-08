(** Logger implementation with level checking and enrichment - now using
    Logger_core *)

(** Enricher signature *)
module type ENRICHER = sig
  type t

  val enrich : t -> Log_event.t -> Log_event.t
end

(** Filter signature *)
module type FILTER = sig
  type t

  val is_included : t -> Log_event.t -> bool
end

(** Logger signature *)
module type S = sig
  type t

  val write :
    t -> ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit

  val is_enabled : t -> Level.t -> bool

  val verbose : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val debug : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val information :
    t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val warning : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val error : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val fatal : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit

  val for_context : t -> string -> Yojson.Safe.t -> t

  val with_enricher : t -> (Log_event.t -> Log_event.t) -> t

  val for_source : t -> string -> t

  val flush : t -> unit

  val close : t -> unit
end

(** Sink function adapter for Logger_core *)
module Sync_sink_fn = struct
  type sink = Composite_sink.sink_fn

  let emit_fn sink event =
    sink.Composite_sink.emit_fn event;
    ()
  ;;

  let flush_fn sink =
    sink.Composite_sink.flush_fn ();
    ()
  ;;

  let close_fn sink =
    sink.Composite_sink.close_fn ();
    ()
  ;;
end

(** Instantiate the logger core with Identity monad *)
module Sync_logger = Logger_core.Make (Logger_core.Identity) (Sync_sink_fn)

(** Logger type is the concrete instantiation *)
type t = Sync_logger.t

(** Create a logger *)
let create ~min_level ~sinks = Sync_logger.create ~min_level ~sinks

(** Write a log event *)
let write t ?exn level message properties =
  ignore (Sync_logger.write t ?exn level message properties)
;;

(** Check if a level is enabled *)
let is_enabled = Sync_logger.is_enabled

(** Level-specific convenience methods *)
let verbose t ?exn message properties =
  ignore (Sync_logger.verbose t ?exn message properties)
;;

let debug t ?exn message properties =
  ignore (Sync_logger.debug t ?exn message properties)
;;

let information t ?exn message properties =
  ignore (Sync_logger.information t ?exn message properties)
;;

let warning t ?exn message properties =
  ignore (Sync_logger.warning t ?exn message properties)
;;

let error t ?exn message properties =
  ignore (Sync_logger.error t ?exn message properties)
;;

let fatal t ?exn message properties =
  ignore (Sync_logger.fatal t ?exn message properties)
;;

(** Context and enrichment *)
let for_context = Sync_logger.for_context

let with_enricher = Sync_logger.with_enricher

let for_source = Sync_logger.for_source

(** Helper to add a property to context *)
let add_property t name value = for_context t name value

(** Helper to add a minimum level filter *)
let add_min_level_filter = Sync_logger.add_min_level_filter

(** Add a custom filter function *)
let add_filter = Sync_logger.add_filter

(** Flush all sinks *)
let flush t = ignore (Sync_logger.flush t)

(** Close all sinks *)
let close t = ignore (Sync_logger.close t)
