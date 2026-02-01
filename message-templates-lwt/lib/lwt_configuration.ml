(** Lwt configuration - fluent API for async logger setup *)

open Message_templates
open Lwt.Syntax

(** Sink configuration type *)
type sink_config =
  { sink_fn: Lwt_sink.sink_fn
  ; min_level: Level.t option }

(** Configuration type *)
type t =
  { min_level: Level.t
  ; sinks: sink_config list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: Filter.t list
  ; context_properties: (string * Yojson.Safe.t) list }

(** Create a new configuration with default minimum level (Information) *)
let create () =
  { min_level= Level.Information
  ; sinks= []
  ; enrichers= []
  ; filters= []
  ; context_properties= [] }
;;

(** Set minimum level for the logger *)
let minimum_level level config = {config with min_level= level}

(** Convenience methods for common levels *)
let verbose config = minimum_level Level.Verbose config

let debug config = minimum_level Level.Debug config

let information config = minimum_level Level.Information config

let warning config = minimum_level Level.Warning config

let error config = minimum_level Level.Error config

let fatal config = minimum_level Level.Fatal config

(** Add an Lwt file sink with optional minimum level override. Note: The sink is
    created lazily on first use to avoid Lwt.t in config *)
let write_to_file
    ?min_level
    ?(rolling = Lwt_file_sink.Infinite)
    ?(output_template = Lwt_file_sink.default_template)
    path
    config =
  (* Use a ref to store the sink once created *)
  let sink_ref = ref None in
  let get_sink () =
    match !sink_ref with
    | Some sink -> Lwt.return sink
    | None ->
        let* sink = Lwt_file_sink.create ~rolling ~output_template path in
        sink_ref := Some sink;
        Lwt.return sink
  in
  let sink_fn =
    { Lwt_sink.emit_fn=
        (fun event ->
          let* sink = get_sink () in
          Lwt_file_sink.emit sink event )
    ; flush_fn=
        (fun () ->
          let* sink = get_sink () in
          Lwt_file_sink.flush sink )
    ; close_fn=
        (fun () ->
          let* sink = get_sink () in
          Lwt_file_sink.close sink ) }
  in
  let sink_config = {sink_fn; min_level} in
  {config with sinks= sink_config :: config.sinks}
;;

(** Add an Lwt console sink with optional minimum level override *)
let write_to_console
    ?min_level
    ?(colors = false)
    ?(stderr_threshold = Level.Warning)
    ?(output_template = Lwt_console_sink.default_template)
    ()
    config =
  let sink =
    Lwt_console_sink.create ~colors ~stderr_threshold ~output_template ()
  in
  let sink_fn =
    { Lwt_sink.emit_fn= (fun event -> Lwt_console_sink.emit sink event)
    ; flush_fn= (fun () -> Lwt_console_sink.flush sink)
    ; close_fn= (fun () -> Lwt_console_sink.close sink) }
  in
  let sink_config = {sink_fn; min_level} in
  {config with sinks= sink_config :: config.sinks}
;;

(** Add a custom Lwt sink function *)
let write_to ?min_level sink_fn config =
  let sink_config = {sink_fn; min_level} in
  {config with sinks= sink_config :: config.sinks}
;;

(** Add an enricher function *)
let enrich_with enricher config =
  {config with enrichers= enricher :: config.enrichers}
;;

(** Add a static property enricher *)
let enrich_with_property name value config =
  let enricher event =
    let props = Log_event.get_properties event in
    let new_props = (name, value) :: props in
    Log_event.create
      ~timestamp:(Log_event.get_timestamp event)
      ~level:(Log_event.get_level event)
      ~message_template:(Log_event.get_message_template event)
      ~rendered_message:(Log_event.get_rendered_message event)
      ~properties:new_props
      ?exception_info:(Log_event.get_exception event)
      ()
  in
  enrich_with enricher config
;;

(** Add a filter *)
let filter_by filter config = {config with filters= filter :: config.filters}

(** Add minimum level filter *)
let filter_by_min_level level config =
  filter_by (Filter.level_filter level) config
;;

(** Create the Lwt logger from configuration *)
let create_logger config =
  let filtered_sinks =
    List.filter_map
      (fun (sink_config : sink_config) ->
        match (sink_config.min_level : Level.t option) with
        | Some sink_min_level ->
            if Level.compare config.min_level sink_min_level >= 0 then
              Some sink_config.sink_fn
            else
              None
        | None -> Some sink_config.sink_fn )
      config.sinks
  in
  let logger =
    Lwt_logger.create ~min_level:config.min_level ~sinks:filtered_sinks
  in
  let logger =
    List.fold_left
      (fun log enricher -> Lwt_logger.with_enricher log enricher)
      logger config.enrichers
  in
  let logger =
    {logger with Lwt_logger.filters= config.filters @ logger.Lwt_logger.filters}
  in
  let logger =
    List.fold_left
      (fun log (name, value) -> Lwt_logger.for_context log name value)
      logger config.context_properties
  in
  logger
;;
