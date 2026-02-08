(** File sink - outputs log events to a file with optional rolling

    The file sink writes log events to files on disk with support for automatic
    log rotation based on time intervals.

    Rolling intervals:
    - Infinite: Never roll (single file)
    - Daily: Create new file each day (appends -YYYYMMDD to filename)
    - Hourly: Create new file each hour (appends -YYYYMMDDHH to filename) *)

type rolling_interval =
  | Infinite  (** Never roll, single log file *)
  | Daily  (** Roll daily at midnight UTC *)
  | Hourly  (** Roll at the start of each hour *)

(** File sink type (opaque) *)
type t

val default_template : string
(** Default file output template: "[{timestamp} [{level}] {message}]" *)

val create : ?output_template:string -> ?rolling:rolling_interval -> string -> t
(** Create a file sink.

    @param output_template Output template with placeholders
    @param rolling Rolling interval for log rotation (default: Infinite)
    @param path Base file path for log files *)

val emit : t -> Log_event.t -> unit
(** Emit a log event to the file *)

val flush : t -> unit
(** Flush the file buffer *)

val close : t -> unit
(** Close the file sink and underlying channel *)
