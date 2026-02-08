(** Millisecond-precision timestamp caching

    Provides efficient timestamp generation by caching results at millisecond
    granularity. Each OCaml domain maintains its own cache for lock-free access.

    Typical usage:
    {[
      let timestamp = Timestamp_cache.get_ptime () in
      let rfc3339 = Timestamp_cache.get_rfc3339 () in
      ()
    ]} *)

(** Cache entry type - exposed for testing *)
type entry = private
  { epoch_ms: int64  (** Milliseconds since Unix epoch *)
  ; ptime: Ptime.t  (** Ptime representation *)
  ; rfc3339: string  (** Pre-formatted RFC3339 string *) }

val get : unit -> entry
(** Get cached timestamp entry, creating or refreshing if necessary

    If caching is disabled, always creates a fresh entry. Otherwise returns
    cached entry if from current millisecond. *)

val get_ptime : unit -> Ptime.t
(** Get current timestamp as Ptime.t (cached at millisecond granularity) *)

val get_rfc3339 : unit -> string
(** Get current timestamp as RFC3339 string (cached at millisecond granularity)
*)

val invalidate : unit -> unit
(** Force cache invalidation - useful for testing *)

val set_enabled : bool -> unit
(** Enable or disable timestamp caching

    When disabled, all timestamp operations bypass the cache. This is useful for
    testing or when precise per-event timing is required.

    @param enabled true to enable caching (default), false to disable *)

val is_enabled : unit -> bool
(** Check if timestamp caching is currently enabled *)
