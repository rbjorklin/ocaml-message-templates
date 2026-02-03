(** Structured shutdown protocol for graceful cleanup

    This module provides a mechanism for registering cleanup handlers and
    executing them during application shutdown with configurable strategies
    including timeout protection.

    Example:
    {[
      let shutdown = Shutdown.create () in

      (* Register cleanup handlers *)
      Shutdown.register shutdown (fun () -> flush_pending_logs ());

      (* Graceful shutdown with timeout *)
      Shutdown.execute shutdown (Shutdown.Graceful 5.0)
    ]} *)

(** Shutdown strategy determines how handlers are executed *)
type shutdown_strategy =
  | Immediate  (** Execute all handlers synchronously, no waiting *)
  | Flush_pending  (** Execute handlers concurrently, wait for all *)
  | Graceful of float  (** Execute with timeout in seconds *)

(** Shutdown controller (opaque) *)
type t

(** Create a new shutdown controller *)
val create : unit -> t
(** @return A new shutdown controller *)

(** Register a cleanup handler *)
val register : t -> (unit -> unit) -> unit
(** Handlers are executed in reverse registration order (LIFO).
    @param t The shutdown controller
    @param handler Function to call during shutdown *)

(** Execute shutdown with specified strategy *)
val execute : t -> shutdown_strategy -> unit
(** @param t The shutdown controller
    @param strategy How to execute handlers
    @raise Failure if shutdown already executed *)

(** Check if shutdown has been executed *)
val is_shutdown : t -> bool
(** @param t The shutdown controller
    @return true if shutdown has already executed *)

(** Reset the shutdown controller (for testing) *)
val reset : t -> unit
(** Clears all handlers and resets shutdown state.
    @param t The shutdown controller *)
