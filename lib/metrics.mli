(** Observability metrics for logging system

    This module provides per-sink metrics collection including event counts,
    error tracking, and latency percentiles. Metrics are thread-safe and
    automatically tracked during logging operations.

    Example:
    {[
      let metrics = Metrics.create () in
      
      (* Record event emission *)
      Metrics.record_event metrics ~sink_id:"file" ~latency_us:1.5;
      
      (* Get sink-specific metrics *)
      let file_metrics = Metrics.get_sink_metrics metrics "file" in
      Printf.printf "Events: %d, Dropped: %d, P95 latency: %.2fμs\n"
        file_metrics.events_total
        file_metrics.events_dropped
        file_metrics.latency_p95_us;
      
      (* Export all metrics as JSON *)
      let json = Metrics.to_json metrics in
      Yojson.Safe.pretty_to_channel stdout json
    ]}
*)

(** Per-sink metrics snapshot *)
type sink_metrics = {
  sink_id: string;
  (** Sink identifier *)
  
  events_total: int;
  (** Total events emitted to this sink *)
  
  events_dropped: int;
  (** Events dropped due to queue overflow *)
  
  events_failed: int;
  (** Events that failed during emission *)
  
  bytes_written: int;
  (** Approximate bytes written to sink *)
  
  last_error: (exn * float) option;
  (** Most recent error (exception * timestamp) if any *)
  
  latency_p50_us: float;
  (** Median latency in microseconds *)
  
  latency_p95_us: float;
  (** 95th percentile latency in microseconds *)
}

(** Metrics tracker (opaque) *)
type t

(** Create a new metrics tracker *)
val create : unit -> t
(** @return A new empty metrics collection *)

(** Record successful event emission *)
val record_event : t -> sink_id:string -> latency_us:float -> unit
(** @param t The metrics tracker
    @param sink_id Identifier for the sink
    @param latency_us Emission latency in microseconds *)

(** Record a dropped event *)
val record_drop : t -> sink_id:string -> unit
(** @param t The metrics tracker
    @param sink_id Identifier for the sink *)

(** Record an emission error *)
val record_error : t -> sink_id:string -> exn -> unit
(** @param t The metrics tracker
    @param sink_id Identifier for the sink
    @param exn The exception that occurred *)

(** Get metrics for a specific sink *)
val get_sink_metrics : t -> string -> sink_metrics option
(** @param t The metrics tracker
    @param sink_id The sink identifier
    @return Metrics snapshot if sink exists, None otherwise *)

(** Get metrics for all sinks *)
val get_all_metrics : t -> sink_metrics list
(** @param t The metrics tracker
    @return List of metrics for all active sinks *)

(** Reset all metrics *)
val reset : t -> unit
(** Clears all accumulated metrics.
    @param t The metrics tracker *)

(** Export metrics as JSON *)
val to_json : t -> Yojson.Safe.t
(** @param t The metrics tracker
    @return JSON representation of all metrics *)
