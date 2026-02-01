(** Global logger - static access like Serilog.Log *)

(** The global logger instance (mutable ref for configuration) *)
let global_logger : Logger.t option ref = ref None

(** Set the global logger *)
let set_logger logger =
  global_logger := Some logger

(** Get the current global logger (if set) *)
let get_logger () =
  !global_logger

(** Close and flush the global logger *)
let close_and_flush () =
  match !global_logger with
  | Some logger -> 
      Logger.flush logger;
      Logger.close logger;
      global_logger := None
  | None -> ()

(** Check if a level is enabled *)
let is_enabled level =
  match !global_logger with
  | Some logger -> Logger.is_enabled logger level
  | None -> false

(** Write with explicit level *)
let write ?exn level message properties =
  match !global_logger with
  | Some logger -> Logger.write logger ?exn level message properties
  | None -> ()

(** Level-specific methods *)
let verbose ?exn message properties =
  write ?exn Level.Verbose message properties

let debug ?exn message properties =
  write ?exn Level.Debug message properties

let information ?exn message properties =
  write ?exn Level.Information message properties

let warning ?exn message properties =
  write ?exn Level.Warning message properties

let error ?exn message properties =
  write ?exn Level.Error message properties

let fatal ?exn message properties =
  write ?exn Level.Fatal message properties

(** Create contextual logger with property (does not modify global) *)
let for_context name value =
  match !global_logger with
  | Some logger -> Logger.for_context logger name value
  | None -> 
      (* Return a dummy logger if none configured *)
      Logger.create ~min_level:Level.Fatal ~sinks:[]

(** Create sub-logger for source (does not modify global) *)
let for_source source_name =
  match !global_logger with
  | Some logger -> Logger.for_source logger source_name
  | None ->
      Logger.create ~min_level:Level.Fatal ~sinks:[]

(** Flush the global logger *)
let flush () =
  match !global_logger with
  | Some logger -> Logger.flush logger
  | None -> ()

(** Close the global logger *)
let close () =
  match !global_logger with
  | Some logger -> 
      Logger.close logger;
      global_logger := None
  | None -> ()
