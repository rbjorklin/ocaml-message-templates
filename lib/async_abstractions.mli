(** Common patterns and utilities for async logging

    This module documents patterns used across Lwt and Eio async backends. It
    demonstrates how async-specific logger implementations share common
    structure while adapting to their respective concurrency models.

    ## Common Pattern

    Both Lwt and Eio async packages follow this pattern:

    1. **Async Sink Functions**: Functions that emit to sinks, returning an
    async effect (Lwt.t or unit)

    2. **Composite Sink**: Applies all sinks in parallel for a given effect

    3. **Configuration Builder**: Fluent API for configuring sinks and filters

    4. **Async Logger**: Methods to write events through configured sinks

    ## Key Design Decisions

    - **Effect abstraction**: Lwt returns promises (unit Lwt.t), Eio runs
      effects directly (unit)
    - **Parallel iteration**: Lwt uses Lwt_list.iter_p, Eio uses List.iter
      within fiber context
    - **File sink initialization**: Lwt delays sink creation, Eio creates
      eagerly

    This module provides documentation and utilities to support this pattern. *)

(** Composite sink pattern implementation

    Given a list of sinks, apply all in parallel (or sequentially on the
    effect), returning combined results. *)
module Async_sink : sig
  (** Build a composite sink from a list of individual sinks.

      The pattern is:
      {[
        let composite emit_list =
         fun event -> iter_p (fun emit -> emit event) emit_list
        ;;
      ]}

      where iter_p uses the async model's parallel iteration *)

  val composite_emits : (Log_event.t -> 'a) list -> Log_event.t -> 'a list
  (** Apply all emit functions to an event *)
end

(** Logger implementation pattern

    Standard logger implementation that:
    - Checks log level is enabled (fast path)
    - Applies enrichers and filters
    - Emits to all configured sinks *)
module Async_logger : sig
  val check_enabled : 'a -> 'b -> bool
  (** Fast path: check if level is enabled *)

  val apply_enrichers : 'a -> 'b -> 'b
  (** Apply all enrichers to an event *)

  val passes_filters : 'a -> 'b -> bool
  (** Check if event passes all filters *)
end

(** Utilities *)
module Async_utils : sig
  val make_composite : (Log_event.t -> unit) list -> Log_event.t -> unit
  (** Convert a list of sink functions to a composite *)

  val type_check : unit -> unit
  (** Check that type definitions are compatible *)
end
