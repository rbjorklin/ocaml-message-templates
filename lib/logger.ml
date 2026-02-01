(** Logger implementation with level checking and enrichment *)

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

(** Logger implementation type *)
type logger_impl =
  { min_level: Level.t
  ; sinks: Composite_sink.sink_fn list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: (Log_event.t -> bool) list
  ; context_properties: (string * Yojson.Safe.t) list
  ; source: string option }

type t = logger_impl

(** Check if a level is enabled *)
let is_enabled t level = Level.compare level t.min_level >= 0

(** Check if event passes all filters *)
let passes_filters t event = List.for_all (fun filter -> filter event) t.filters

(** Apply all enrichers to an event *)
let apply_enrichers t event =
  List.fold_left (fun ev enricher -> enricher ev) event t.enrichers
;;

(** Add context properties to an event *)
let add_context_properties t event =
  if t.context_properties = [] then
    event
  else
    let current_props = Log_event.get_properties event in
    let new_props = t.context_properties @ current_props in
    (* Re-create event with merged properties *)
    Log_event.create
      ~timestamp:(Log_event.get_timestamp event)
      ~level:(Log_event.get_level event)
      ~message_template:(Log_event.get_message_template event)
      ~rendered_message:(Log_event.get_rendered_message event)
      ~properties:new_props
      ?exception_info:(Log_event.get_exception event)
      ()
;;

(** Core write method *)
let write t ?exn level message_template properties =
  (* Fast path: check minimum level first *)
  if not (is_enabled t level) then
    ()
  else
    (* Create the log event *)
    let rendered_message =
      Runtime_helpers.render_template message_template properties
    in
    let event =
      Log_event.create ~level ~message_template ~rendered_message ~properties
        ?exception_info:exn ()
    in

    (* Apply enrichment pipeline *)
    let event = apply_enrichers t event in
    let event = add_context_properties t event in

    (* Check filters *)
    if not (passes_filters t event) then
      ()
    else
      (* Emit to all sinks *)
      List.iter (fun sink -> sink.Composite_sink.emit_fn event) t.sinks
;;

(** Level-specific convenience methods *)
let verbose t ?exn message properties =
  write t ?exn Level.Verbose message properties
;;

let debug t ?exn message properties =
  write t ?exn Level.Debug message properties
;;

let information t ?exn message properties =
  write t ?exn Level.Information message properties
;;

let warning t ?exn message properties =
  write t ?exn Level.Warning message properties
;;

let error t ?exn message properties =
  write t ?exn Level.Error message properties
;;

let fatal t ?exn message properties =
  write t ?exn Level.Fatal message properties
;;

(** Create a contextual logger with additional property *)
let for_context t name value =
  {t with context_properties= (name, value) :: t.context_properties}
;;

(** Add an enricher function *)
let with_enricher t enricher = {t with enrichers= enricher :: t.enrichers}

(** Create a sub-logger for a specific source *)
let for_source t source_name = {t with source= Some source_name}

(** Create a logger *)
let create ~min_level ~sinks =
  { min_level
  ; sinks
  ; enrichers= []
  ; filters= []
  ; context_properties= []
  ; source= None }
;;

(** Helper to add a property to context *)
let add_property t name value = for_context t name value

(** Helper to add a minimum level filter *)
let add_min_level_filter t min_level =
  let filter event = Level.compare (Log_event.get_level event) min_level >= 0 in
  {t with filters= filter :: t.filters}
;;

(** Flush all sinks *)
let flush t = List.iter (fun sink -> sink.Composite_sink.flush_fn ()) t.sinks

(** Close all sinks *)
let close t = List.iter (fun sink -> sink.Composite_sink.close_fn ()) t.sinks
