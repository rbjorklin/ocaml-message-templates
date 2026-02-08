(** Eio logger - sync logger implementation for Eio fibers *)

open Message_templates

(** Logger implementation type *)
type t =
  { min_level: Level.t
  ; sinks: (Eio_sink.sink_fn * Level.t option) list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: (Log_event.t -> bool) list
  ; context_properties: (string * Yojson.Safe.t) list
  ; source: string option
  ; sw: Eio.Switch.t option }

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
  let ambient_props = Log_context.current_properties () in
  let correlation_id = Log_context.get_correlation_id () in
  if ambient_props = [] && t.context_properties = [] && correlation_id = None
  then
    event
  else
    let current_props = Log_event.get_properties event in
    let new_props = ambient_props @ t.context_properties @ current_props in
    Log_event.create
      ~timestamp:(Log_event.get_timestamp event)
      ~level:(Log_event.get_level event)
      ~message_template:(Log_event.get_message_template event)
      ~rendered_message:(Log_event.get_rendered_message event)
      ~properties:new_props
      ?exception_info:(Log_event.get_exception event)
      ?correlation_id:
        ( match correlation_id with
        | None -> Log_event.get_correlation_id event
        | Some _ -> correlation_id )
      ()
;;

(** Core write method *)
let write t ?exn level message_template properties =
  if not (is_enabled t level) then
    ()
  else
    let rendered_message =
      Runtime_helpers.render_template message_template properties
    in
    let correlation_id = Log_context.get_correlation_id () in
    let event =
      Log_event.create ~level ~message_template ~rendered_message ~properties
        ?exception_info:exn ?correlation_id ()
    in
    let event = apply_enrichers t event in
    let event = add_context_properties t event in
    if not (passes_filters t event) then
      ()
    else
      (* Emit to all sinks with per-sink level filtering *)
      List.iter
        (fun (sink_fn, min_level) ->
          match min_level with
          | Some min_lvl when Level.compare level min_lvl < 0 -> ()
          | _ -> sink_fn.Eio_sink.emit_fn event )
        t.sinks
;;

(** Fire-and-forget logging - runs in background fiber *)
let write_async t ?exn level message_template properties =
  match t.sw with
  | Some sw ->
      Eio.Fiber.fork ~sw (fun () ->
          try write t ?exn level message_template properties
          with exn ->
            Printf.eprintf "Logging error: %s\n" (Printexc.to_string exn) )
  | None -> write t ?exn level message_template properties
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

(** Create a contextual logger with additional property *)
let for_context t name value =
  {t with context_properties= (name, value) :: t.context_properties}
;;

(** Add an enricher function *)
let with_enricher t enricher = {t with enrichers= enricher :: t.enrichers}

(** Create a sub-logger for a specific source *)
let for_source t source_name = {t with source= Some source_name}

(** Create a logger *)
let create ?sw ~min_level ~sinks () =
  { min_level
  ; sinks
  ; enrichers= []
  ; filters= []
  ; context_properties= []
  ; source= None
  ; sw }
;;

(** Flush all sinks *)
let flush t =
  List.iter (fun (sink_fn, _) -> sink_fn.Eio_sink.flush_fn ()) t.sinks
;;

(** Close all sinks *)
let close t =
  List.iter (fun (sink_fn, _) -> sink_fn.Eio_sink.close_fn ()) t.sinks
;;
