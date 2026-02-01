(** Configuration builder for loggers - fluent API *)

type sink_config = {
  sink_fn : Composite_sink.sink_fn;
  min_level : Level.t option;
}

type t = {
  min_level : Level.t;
  sinks : sink_config list;
  enrichers : (Log_event.t -> Log_event.t) list;
  filters : Filter.t list;
  context_properties : (string * Yojson.Safe.t) list;
}

(** Create a new configuration with default minimum level (Information) *)
let create () = {
  min_level = Level.Information;
  sinks = [];
  enrichers = [];
  filters = [];
  context_properties = [];
}

(** Set minimum level for the logger *)
let minimum_level level config =
  { config with min_level = level }

(** Convenience methods for common levels *)
let verbose config = minimum_level Level.Verbose config
let debug config = minimum_level Level.Debug config
let information config = minimum_level Level.Information config
let warning config = minimum_level Level.Warning config
let error config = minimum_level Level.Error config
let fatal config = minimum_level Level.Fatal config

(** Add a file sink with optional minimum level override *)
let write_to_file ?min_level ?(rolling=File_sink.Infinite) ?(output_template=File_sink.default_template) path config =
  let file_sink = File_sink.create ~rolling ~output_template path in
  let sink_fn = {
    Composite_sink.emit_fn = (fun event -> File_sink.emit file_sink event);
    flush_fn = (fun () -> File_sink.flush file_sink);
    close_fn = (fun () -> File_sink.close file_sink);
  } in
  let sink_config = { sink_fn; min_level } in
  { config with sinks = sink_config :: config.sinks }

(** Add a console sink with optional minimum level override *)
let write_to_console ?min_level ?(colors=false) ?(stderr_threshold=Level.Warning) ?(output_template=Console_sink.default_template) () config =
  let console_sink = Console_sink.create ~colors ~stderr_threshold ~output_template () in
  let sink_fn = {
    Composite_sink.emit_fn = (fun event -> Console_sink.emit console_sink event);
    flush_fn = (fun () -> Console_sink.flush console_sink);
    close_fn = (fun () -> Console_sink.close console_sink);
  } in
  let sink_config = { sink_fn; min_level } in
  { config with sinks = sink_config :: config.sinks }

(** Add a null sink (discards all events) *)
let write_to_null ?min_level () config =
  let null_sink = Null_sink.create () in
  let sink_fn = {
    Composite_sink.emit_fn = (fun event -> Null_sink.emit null_sink event);
    flush_fn = (fun () -> Null_sink.flush null_sink);
    close_fn = (fun () -> Null_sink.close null_sink);
  } in
  let sink_config = { sink_fn; min_level } in
  { config with sinks = sink_config :: config.sinks }

(** Add a custom sink function *)
let write_to ?min_level sink_fn config =
  let sink_config = { sink_fn; min_level } in
  { config with sinks = sink_config :: config.sinks }

(** Add an enricher function *)
let enrich_with enricher config =
  { config with enrichers = enricher :: config.enrichers }

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

(** Add a filter *)
let filter_by filter config =
  { config with filters = filter :: config.filters }

(** Add minimum level filter *)
let filter_by_min_level level config =
  filter_by (Filter.level_filter level) config

(** Create the logger from configuration *)
let create_logger config =
  (* Filter sinks by minimum level if specified *)
  let filtered_sinks : Composite_sink.sink_fn list = 
    List.filter_map (fun (sink_config : sink_config) ->
      match (sink_config.min_level : Level.t option) with
      | Some sink_min_level ->
          (* Only include this sink if logger's min_level >= sink's min_level *)
          if Level.compare config.min_level sink_min_level >= 0 then
            Some sink_config.sink_fn
          else
            None
      | None -> Some sink_config.sink_fn
    ) config.sinks
  in
  
  (* Create the logger *)
  let logger = Logger.create ~min_level:config.min_level ~sinks:filtered_sinks in
  
  (* Add enrichers *)
  let logger = List.fold_left (fun log enricher -> 
    Logger.with_enricher log enricher
  ) logger config.enrichers
  in
  
  (* Add filters *)
  let logger = { logger with 
    Logger.filters = config.filters @ logger.Logger.filters 
  } in
  
  (* Add context properties *)
  let logger = List.fold_left (fun log (name, value) ->
    Logger.for_context log name value
  ) logger config.context_properties
  in
  
  logger
