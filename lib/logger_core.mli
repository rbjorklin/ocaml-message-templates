(** Core logger functionality shared across sync, Lwt, and Eio implementations

    This module provides a functor-based approach to sharing logger logic across
    different effect systems (sync, Lwt, Eio). The functor is parameterized by a
    monad and a sink implementation. *)

(** Monad signature for the logger's effect system *)
module type MONAD = sig
  (** The type of computations returning 'a *)
  type 'a t

  val return : 'a -> 'a t
  (** Wrap a value in the monad *)

  val bind : 'a t -> ('a -> 'b t) -> 'b t
  (** Monadic bind *)

  val iter_p : ('a -> unit t) -> 'a list -> unit t
  (** Parallel iteration over a list *)
end

(** Identity monad for synchronous operations *)
module Identity : sig
  type 'a t = 'a

  val return : 'a -> 'a t

  val bind : 'a t -> ('a -> 'b t) -> 'b t

  val iter_p : ('a -> unit t) -> 'a list -> unit t
end

(** Make functor - creates a logger for the given monad and sink.

    The Sink_fn module provides functions that return unit M.t:
    - emit_fn: sink -> Log_event.t -> unit M.t
    - flush_fn: sink -> unit M.t
    - close_fn: sink -> unit M.t

    For Identity monad, these return plain unit. For Lwt, these return unit
    Lwt.t *)
module Make
    (M : MONAD)
    (Sink_fn : sig
      type sink

      val emit_fn : sink -> Log_event.t -> unit M.t

      val flush_fn : sink -> unit M.t

      val close_fn : sink -> unit M.t
    end) : sig
  type t =
    { min_level: Level.t
    ; sinks: (Sink_fn.sink * Level.t option) list
    ; enrichers: (Log_event.t -> Log_event.t) list
    ; filters: (Log_event.t -> bool) list
    ; context_properties: (string * Yojson.Safe.t) list
    ; source: string option }

  val create :
    min_level:Level.t -> sinks:(Sink_fn.sink * Level.t option) list -> t

  val write :
       t
    -> ?exn:exn
    -> Level.t
    -> string
    -> (string * Yojson.Safe.t) list
    -> unit M.t

  val is_enabled : t -> Level.t -> bool

  val verbose :
    t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit M.t

  val debug :
    t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit M.t

  val information :
    t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit M.t

  val warning :
    t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit M.t

  val error :
    t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit M.t

  val fatal :
    t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit M.t

  val for_context : t -> string -> Yojson.Safe.t -> t

  val with_enricher : t -> (Log_event.t -> Log_event.t) -> t

  val for_source : t -> string -> t

  val flush : t -> unit M.t

  val close : t -> unit M.t

  val add_min_level_filter : t -> Level.t -> t

  val add_filter : t -> (Log_event.t -> bool) -> t
end
