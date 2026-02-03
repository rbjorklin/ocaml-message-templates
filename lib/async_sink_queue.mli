(** Non-blocking event queue for async sink batching

    This module provides a queue-based wrapper around synchronous sinks,
    allowing events to be enqueued non-blockingly and flushed asynchronously
    in the background. This decouples the logger from I/O latency.

    Example:
    {[
      let sink = File_sink.create "app.log" in
      let queue = Async_sink_queue.create default_config sink in
      
      (* Enqueue is non-blocking ~1μs *)
      Async_sink_queue.enqueue queue event;
      
      (* Background thread flushes periodically *)
      let depth = Async_sink_queue.get_queue_depth queue in
      Printf.printf "Pending events: %d\n" depth;
      
      (* Graceful shutdown *)
      Async_sink_queue.flush queue;
      Async_sink_queue.close queue;
    ]}
*)

(** Configuration for async queue *)
type config = {
  max_queue_size: int;         (** Max events in queue, drops oldest if exceeded *)
  flush_interval_ms: int;      (** Milliseconds between background flushes *)
  batch_size: int;             (** Events to flush per batch *)
  back_pressure_threshold: int; (** Warn if queue depth exceeds this *)
  error_handler: exn -> unit;  (** Called when sink emit fails *)
}

(** Default configuration *)
val default_config : config

(** Async sink queue type (opaque) *)
type t

(** Create a queued wrapper around a synchronous sink *)
val create : config -> (Log_event.t -> unit) -> t
(** @param config Queue configuration
    @param sink_fn Function that emits events to the underlying sink *)

(** Non-blocking enqueue - drops oldest if queue full *)
val enqueue : t -> Log_event.t -> unit
(** @param t The queue
    @param event Event to enqueue *)

(** Current queue depth *)
val get_queue_depth : t -> int
(** @param t The queue
    @return Number of pending events *)

(** Statistics about queue operations *)
type stats = {
  mutable total_enqueued: int;
  mutable total_emitted: int;
  mutable total_dropped: int;
  mutable total_errors: int;
}

(** Get queue statistics *)
val get_stats : t -> stats
(** @param t The queue
    @return Statistics about queue behavior *)

(** Flush all queued events to sink *)
val flush : t -> unit
(** Synchronously flushes all pending events.
    @param t The queue *)

(** Check if queue is alive and operating *)
val is_alive : t -> bool
(** @param t The queue
    @return true if background thread is running *)

(** Gracefully close the queue *)
val close : t -> unit
(** Flushes all pending events and stops background thread.
    @param t The queue *)
