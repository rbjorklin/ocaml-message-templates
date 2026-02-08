(** Millisecond-precision timestamp caching

    Reduces syscall overhead by caching timestamps at millisecond granularity.
    Uses domain-local storage for thread safety without locks. *)

(** Cache entry containing pre-computed timestamp values *)
type entry =
  { epoch_ms: int64  (** Milliseconds since Unix epoch *)
  ; ptime: Ptime.t  (** Ptime representation *)
  ; rfc3339: string  (** Pre-formatted RFC3339 string *) }

(** Cache state - mutable for updates within a domain *)
type cache_state = {mutable cached: entry option}

(** Global flag to enable/disable caching - atomic for thread safety *)
let caching_enabled = Atomic.make true

(** Domain-local cache instance - each domain has its own cache *)
let domain_cache = Domain.DLS.new_key (fun () -> {cached= None})

(** Get current time in milliseconds since epoch *)
let now_ms () : int64 = Int64.of_float (Unix.gettimeofday () *. 1000.0)

(** Create a new cache entry from current time *)
let create_entry () : entry =
  let epoch_ms = now_ms () in
  let float_s = Int64.to_float epoch_ms /. 1000.0 in
  match Ptime.of_float_s float_s with
  | Some ptime ->
      let rfc3339 = Ptime.to_rfc3339 ~frac_s:3 ptime in
      {epoch_ms; ptime; rfc3339}
  | None -> {epoch_ms; ptime= Ptime.epoch; rfc3339= "1970-01-01T00:00:00.000Z"}
;;

(** Enable or disable timestamp caching *)
let set_enabled enabled = Atomic.set caching_enabled enabled

(** Check if timestamp caching is enabled *)
let is_enabled () = Atomic.get caching_enabled

(** Get cached timestamp entry, refreshing if needed

    If caching is disabled, always returns a fresh entry. If the cached entry is
    from a different millisecond, creates a new one. Otherwise returns the
    cached entry. *)
let get () : entry =
  if not (is_enabled ()) then
    create_entry ()
  else
    let cache = Domain.DLS.get domain_cache in
    let current_ms = now_ms () in
    match cache.cached with
    | Some entry when entry.epoch_ms = current_ms ->
        (* Cache hit - same millisecond *)
        entry
    | _ ->
        (* Cache miss - need to refresh *)
        let new_entry = create_entry () in
        cache.cached <- Some new_entry;
        new_entry
;;

(** Get current timestamp as Ptime.t *)
let get_ptime () : Ptime.t = (get ()).ptime

(** Get current timestamp as RFC3339 string *)
let get_rfc3339 () : string = (get ()).rfc3339

(** Force cache refresh (useful for testing or after long pauses) *)
let invalidate () : unit =
  let cache = Domain.DLS.get domain_cache in
  cache.cached <- None
;;
