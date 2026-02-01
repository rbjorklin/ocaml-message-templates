(** Log levels ordered by severity (lowest to highest)

    Six standard log levels following syslog conventions:
    - Verbose: Detailed diagnostic information
    - Debug: Information useful for debugging
    - Information: Normal operational messages (default)
    - Warning: Suspicious or degraded conditions
    - Error: Functionality unavailable
    - Fatal: System failure, needs immediate attention *)

type t =
  | Verbose
  | Debug
  | Information
  | Warning
  | Error
  | Fatal

val to_int : t -> int
(** Convert level to integer for ordering comparisons *)

val of_string : string -> t option
(** Parse level from string (case-insensitive). Accepts full names ("Debug"),
    short names ("dbg"), or abbreviations ("DBG"). *)

val to_string : t -> string
(** Convert level to full string representation *)

val to_short_string : t -> string
(** Convert level to short 3-character string (e.g., DBG, INF) *)

val compare : t -> t -> int
(** Compare two levels. Returns negative if first < second. *)

val ( >= ) : t -> t -> bool
(** Check if level a is greater than or equal to level b *)

val ( < ) : t -> t -> bool
(** Check if level a is less than level b *)
