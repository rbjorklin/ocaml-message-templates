(** Composite sink - routes log events to multiple sinks

    A composite sink allows you to send log events to multiple destinations
    simultaneously. For example, you might want to log to both console and file.

    Example:
    {[
      let console = Console_sink.create () in
      let file = File_sink.create "app.log" in
      let composite = Composite_sink.create [console; file] in
      Logger.create ~min_level:Level.Information ~sinks:[composite]
    ]} *)

(** Sink function record for composite routing *)
type sink_fn =
  { emit_fn: Log_event.t -> unit
  ; flush_fn: unit -> unit
  ; close_fn: unit -> unit }

(** Composite sink is a list of sink functions *)
type t = sink_fn list

val emit : t -> Log_event.t -> unit
(** Emit an event to all sinks in the composite *)

val flush : t -> unit
(** Flush all sinks in the composite *)

val close : t -> unit
(** Close all sinks in the composite *)

val create : sink_fn list -> t
(** Create a composite sink from a list of sink functions *)
