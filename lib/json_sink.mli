(** JSON sink - outputs log events as pure CLEF/JSON format

    This sink writes log events in Compact Log Event Format (CLEF), one JSON
    object per line (NDJSON format).

    CLEF fields:
    - [@t]: Timestamp in RFC3339 format
    - [@mt]: Original message template
    - [@l]: Log level
    - [@m]: Rendered message
    - [CorrelationId]: Optional correlation ID
    - Custom properties as additional fields

    Example output:
    {[
      {"@t":"2026-01-31T12:00:00Z","@mt":"User {name} logged in","@l":"Information","@m":"User alice logged in","name":"alice"}
    ]} *)

(** JSON sink type (opaque) *)
type t

val emit : t -> Log_event.t -> unit
(** Emit a log event as JSON to the output *)

val flush : t -> unit
(** Flush the output buffer *)

val close : t -> unit
(** Close the underlying output channel *)

val create : string -> t
(** Create a new JSON sink writing to a file path *)

val of_out_channel : out_channel -> t
(** Create a JSON sink from an existing output channel *)
