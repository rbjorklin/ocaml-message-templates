(** Memory usage monitoring and limits for queues

    This module tracks memory usage in queues and provides mechanisms to enforce
    limits and trigger cleanup when memory usage exceeds configured thresholds.

    Example:
    {[
      let config =
        { max_queue_bytes= 100 * 1024 * 1024
        ; (* 100 MB *)
          max_event_size_bytes= 1024 * 1024
        ; (* 1 MB per event *)
          on_limit_exceeded=
            (fun () -> Printf.eprintf "Queue memory limit exceeded!\n") }
      in

      let tracker = Memory_tracking.create config in

      (* Track memory usage *)
      Memory_tracking.record_enqueue tracker ~bytes:1024;

      if Memory_tracking.is_over_limit tracker then
        Memory_tracking.trim_to_limit tracker
    ]} *)

(** Configuration for memory tracking *)
type config =
  { max_queue_bytes: int  (** Maximum bytes allowed in queue *)
  ; max_event_size_bytes: int  (** Maximum size for single event *)
  ; on_limit_exceeded: unit -> unit  (** Callback when limit exceeded *) }

(** Memory tracker (opaque) *)
type t

(** Create a new memory tracker *)
val create : config -> t
(** @param config Memory tracking configuration *)

(** Update configuration *)
val set_config : t -> config -> unit
(** @param t The memory tracker
    @param config New configuration *)

(** Record memory usage for an enqueued event *)
val record_enqueue : t -> bytes:int -> unit
(** @param t The memory tracker
    @param bytes Size of event in bytes *)

(** Record memory freed from a dequeued event *)
val record_dequeue : t -> bytes:int -> unit
(** @param t The memory tracker
    @param bytes Size of event in bytes *)

(** Get current memory usage in bytes *)
val get_usage : t -> int
(** @param t The memory tracker
    @return Current bytes used *)

(** Check if memory limit is exceeded *)
val is_over_limit : t -> bool
(** @param t The memory tracker
    @return true if usage exceeds max_queue_bytes *)

(** Trim memory to within limits (callback decides how) *)
val trim_to_limit : t -> unit
(** Calls on_limit_exceeded callback when limit exceeded.
    @param t The memory tracker *)

(** Get current configuration *)
val get_config : t -> config
(** @param t The memory tracker
    @return Current configuration *)

(** Default configuration *)
val default_config : config
(** Reasonable defaults for memory tracking *)
