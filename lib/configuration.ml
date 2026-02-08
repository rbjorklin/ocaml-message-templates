(** Configuration builder for loggers - fluent API *)

type sink_config =
  { sink_fn: Composite_sink.sink_fn
  ; min_level: Level.t option }

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

(** Generic helper to add a sink from a sink implementation module *)
let add_sink ?min_level ~create ~emit ~flush ~close config =
  let sink = create () in
  let sink_fn =
    { Composite_sink.emit_fn=
        (fun event ->
          match min_level with
          | Some min_lvl
            when Level.compare (Log_event.get_level event) min_lvl < 0 ->
              () (* Skip - event level too low for this sink *)
          | _ -> emit sink event )
    ; flush_fn= (fun () -> flush sink)
    ; close_fn= (fun () -> close sink)
    ; min_level }
  in
  {config with sinks= {sink_fn; min_level} :: config.sinks}
;;

(** Add a file sink with optional minimum level override *)
let write_to_file
    ?min_level
    ?(rolling = File_sink.Infinite)
    ?(output_template = File_sink.default_template)
    path
    config =
  add_sink ?min_level
    ~create:(fun () -> File_sink.create ~rolling ~output_template path)
    ~emit:File_sink.emit ~flush:File_sink.flush ~close:File_sink.close config
;;

(** Add a console sink with optional minimum level override *)
let write_to_console
    ?min_level
    ?(colors = false)
    ?(stderr_threshold = Level.Warning)
    ?(output_template = Console_sink.default_template)
    ()
    config =
  add_sink ?min_level
    ~create:(fun () ->
      Console_sink.create ~colors ~stderr_threshold ~output_template () )
    ~emit:Console_sink.emit ~flush:Console_sink.flush ~close:Console_sink.close
    config
;;

(** Add a null sink (discards all events) *)
let write_to_null ?min_level () config =
  add_sink ?min_level ~create:Null_sink.create ~emit:Null_sink.emit
    ~flush:Null_sink.flush ~close:Null_sink.close config
;;

(** Add a custom sink function with optional minimum level override. If both the
    sink_fn has a min_level and one is provided here, the more restrictive
    (higher) level is used. *)
let write_to ?min_level (sink_config : sink_config) config =
  let effective_min_level =
    match (sink_config.min_level, min_level) with
    | Some sink_level, Some cfg_level ->
        if Level.compare sink_level cfg_level > 0 then
          Some sink_level
        else
          Some cfg_level
    | Some level, None -> Some level
    | None, Some level -> Some level
    | None, None -> None
  in
  (* Wrap emit_fn with level checking *)
  let wrapped_emit_fn event =
    match effective_min_level with
    | Some min_lvl when Level.compare (Log_event.get_level event) min_lvl < 0 ->
        () (* Skip - event level too low for this sink *)
    | _ -> sink_config.sink_fn.Composite_sink.emit_fn event
  in
  let new_sink_fn =
    { sink_config.sink_fn with
      Composite_sink.emit_fn= wrapped_emit_fn
    ; min_level= effective_min_level }
  in
  let new_sink_config =
    {sink_fn= new_sink_fn; min_level= effective_min_level}
  in
  {config with sinks= new_sink_config :: config.sinks}
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

(** Create the logger from configuration *)
let create_logger config =
  (* Extract sink functions - per-sink level filtering happens at runtime in
     Composite_sink.emit, so we pass all sinks through *)
  let all_sinks : Composite_sink.sink_fn list =
    List.map
      (fun (sink_config : sink_config) -> sink_config.sink_fn)
      config.sinks
  in

  (* Create the logger *)
  let logger = Logger.create ~min_level:config.min_level ~sinks:all_sinks in

  (* Add enrichers *)
  let logger =
    List.fold_left
      (fun log enricher -> Logger.with_enricher log enricher)
      logger config.enrichers
  in

  (* Add filters *)
  let logger =
    List.fold_left
      (fun log filter -> Logger.add_filter log filter)
      logger config.filters
  in

  (* Add context properties *)
  let logger =
    List.fold_left
      (fun log (name, value) -> Logger.for_context log name value)
      logger config.context_properties
  in

  logger
;;
