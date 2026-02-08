(** Millisecond-precision timestamp caching *)

type entry =
  { epoch_ms: int64
  ; ptime: Ptime.t
  ; rfc3339: string }

type cache_state = {mutable cached: entry option}

let caching_enabled = Atomic.make true

let domain_cache = Domain.DLS.new_key (fun () -> {cached= None})

let now_ms () = Int64.of_float (Unix.gettimeofday () *. 1000.0)

let create_entry () =
  let epoch_ms = now_ms () in
  let float_s = Int64.to_float epoch_ms /. 1000.0 in
  match Ptime.of_float_s float_s with
  | Some ptime ->
      let rfc3339 = Ptime.to_rfc3339 ~frac_s:3 ptime in
      {epoch_ms; ptime; rfc3339}
  | None -> {epoch_ms; ptime= Ptime.epoch; rfc3339= "1970-01-01T00:00:00.000Z"}
;;

let set_enabled enabled = Atomic.set caching_enabled enabled

let is_enabled () = Atomic.get caching_enabled

let get () =
  if not (is_enabled ()) then
    create_entry ()
  else
    let cache = Domain.DLS.get domain_cache in
    let current_ms = now_ms () in
    match cache.cached with
    | Some entry when entry.epoch_ms = current_ms -> entry
    | _ ->
        let new_entry = create_entry () in
        cache.cached <- Some new_entry;
        new_entry
;;

let get_ptime () = (get ()).ptime

let get_rfc3339 () = (get ()).rfc3339

let invalidate () =
  let cache = Domain.DLS.get domain_cache in
  cache.cached <- None
;;
