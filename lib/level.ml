(** Log levels ordered by severity (lowest to highest) *)
type t =
  | Verbose     (* 0 - Most detailed, rarely enabled *)
  | Debug       (* 1 - Internal system events *)
  | Information (* 2 - Normal operational messages (default) *)
  | Warning     (* 3 - Suspicious or degraded conditions *)
  | Error       (* 4 - Functionality unavailable *)
  | Fatal       (* 5 - System failure, needs immediate attention *)

(** Convert level to integer for ordering *)
let to_int = function
  | Verbose -> 0
  | Debug -> 1
  | Information -> 2
  | Warning -> 3
  | Error -> 4
  | Fatal -> 5

(** Convert level from string *)
let of_string = function
  | "Verbose" | "verbose" | "VRB" | "vrb" -> Some Verbose
  | "Debug" | "debug" | "DBG" | "dbg" -> Some Debug
  | "Information" | "information" | "INF" | "inf" -> Some Information
  | "Warning" | "warning" | "WRN" | "wrn" -> Some Warning
  | "Error" | "error" | "ERR" | "err" -> Some Error
  | "Fatal" | "fatal" | "FTL" | "ftl" -> Some Fatal
  | _ -> None

(** Convert level to full string *)
let to_string = function
  | Verbose -> "Verbose"
  | Debug -> "Debug"
  | Information -> "Information"
  | Warning -> "Warning"
  | Error -> "Error"
  | Fatal -> "Fatal"

(** Convert level to short 3-character string *)
let to_short_string = function
  | Verbose -> "VRB"
  | Debug -> "DBG"
  | Information -> "INF"
  | Warning -> "WRN"
  | Error -> "ERR"
  | Fatal -> "FTL"

(** Compare two levels (returns negative if first < second) *)
let compare a b =
  Int.compare (to_int a) (to_int b)

(** Check if level a is greater than or equal to level b *)
let (>=) a b =
  compare a b >= 0

(** Check if level a is less than level b *)
let (<) a b =
  compare a b < 0
