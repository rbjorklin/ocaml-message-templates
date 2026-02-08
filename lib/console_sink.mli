(** Console sink - outputs log events to stdout/stderr

    The console sink provides formatted log output to the terminal with optional
    color support. Events at Error level and above go to stderr, others go to
    stdout.

    Color codes by level:
    - Verbose: Dark gray
    - Debug: Cyan
    - Information: Green
    - Warning: Yellow
    - Error: Red
    - Fatal: Magenta *)

(** Console sink type (opaque) *)
type t

val default_template : string
(** Default console output template: "[{timestamp} [{level}] {message}]" *)

val create :
     ?output_template:string
  -> ?colors:bool
  -> ?stderr_threshold:Level.t
  -> unit
  -> t
(** Create a console sink.

    @param output_template
      Output template with placeholders [{timestamp}, {level}, {message}]
    @param colors Enable ANSI color codes (default: true)
    @param stderr_threshold Minimum level for stderr output (default: Error) *)

val emit : t -> Log_event.t -> unit
(** Emit a log event to the console *)

val flush : t -> unit
(** Flush the output buffer *)

val close : t -> unit
(** Close the console sink (no-op for console) *)
