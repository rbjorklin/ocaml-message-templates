(** Configuration builder for loggers - fluent API

    Provides a fluent builder pattern for configuring loggers. Configuration is
    immutable - each operation returns a new config.

    Example:
    {[
      let logger =
        Configuration.create ()
        |> Configuration.minimum_level Level.Debug
        |> Configuration.write_to_console ~colors:true ()
        |> Configuration.write_to_file "/var/log/app.log"
        |> Configuration.build
      ;;
    ]} *)

(** Configuration type (opaque) *)
type t

type sink_config

val sink_config : ?min_level:Level.t -> Composite_sink.sink_fn -> sink_config
(** Create a sink configuration from a sink function with optional minimum level
*)

val create : unit -> t
(** Create a new configuration with default minimum level (Information) *)

val minimum_level : Level.t -> t -> t
(** Set minimum level for the logger *)

val verbose : t -> t
(** Set minimum level to Verbose *)

val debug : t -> t
(** Set minimum level to Debug *)

val information : t -> t
(** Set minimum level to Information (default) *)

val warning : t -> t
(** Set minimum level to Warning *)

val error : t -> t
(** Set minimum level to Error *)

val fatal : t -> t
(** Set minimum level to Fatal *)

val write_to_file :
     ?min_level:Level.t
  -> ?rolling:File_sink.rolling_interval
  -> ?output_template:string
  -> string
  -> t
  -> t
(** Add a file sink with optional minimum level override *)

val write_to_console :
     ?min_level:Level.t
  -> ?colors:bool
  -> ?stderr_threshold:Level.t
  -> ?output_template:string
  -> unit
  -> t
  -> t
(** Add a console sink with optional configuration *)

val write_to_null : ?min_level:Level.t -> unit -> t -> t
(** Add a null sink (discards all events) *)

val write_to : ?min_level:Level.t -> sink_config -> t -> t
(** Add a custom sink to the configuration *)

val enrich_with : (Log_event.t -> Log_event.t) -> t -> t
(** Add an enricher function to modify events *)

val enrich_with_property : string -> Yojson.Safe.t -> t -> t
(** Add a context property to all events *)

val filter_by : Filter.t -> t -> t
(** Add a filter to the configuration *)

val filter_by_min_level : Level.t -> t -> t
(** Add minimum level filter *)

val create_logger : t -> Logger.t
(** Build a logger from the configuration *)
