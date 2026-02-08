(** Log levels ordered by severity (lowest to highest) *)

type t =
  | Verbose  (** 0 - Most detailed, rarely enabled *)
  | Debug  (** 1 - Internal system events *)
  | Information  (** 2 - Normal operational messages (default) *)
  | Warning  (** 3 - Suspicious or degraded conditions *)
  | Error  (** 4 - Functionality unavailable *)
  | Fatal  (** 5 - System failure, needs immediate attention *)

val to_int : t -> int
(** Convert level to integer for ordering *)

val of_string : string -> t option
(** Convert level from string (case-insensitive) *)

val to_string : t -> string
(** Convert level to full string *)

val to_short_string : t -> string
(** Convert level to short 3-character string *)

val compare : t -> t -> int
(** Compare two levels (returns negative if first < second) *)

val ( >= ) : t -> t -> bool
(** Check if level a is greater than or equal to level b *)

val ( < ) : t -> t -> bool
(** Check if level a is less than level b *)

val ( > ) : t -> t -> bool
(** Check if level a is greater than level b *)

val ( <= ) : t -> t -> bool
(** Check if level a is less than or equal to level b *)

val ( = ) : t -> t -> bool
(** Check if two levels are equal *)

val ( <> ) : t -> t -> bool
(** Check if two levels are not equal *)
