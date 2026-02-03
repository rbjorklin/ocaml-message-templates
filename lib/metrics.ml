(** Observability metrics for logging system *)

type sink_metrics = {
  sink_id: string;
  events_total: int;
  events_dropped: int;
  events_failed: int;
  bytes_written: int;
  last_error: (exn * float) option;
  latency_p50_us: float;
  latency_p95_us: float;
}

(** Internal sink data *)
type sink_data = {
  mutable events_total: int;
  mutable events_dropped: int;
  mutable events_failed: int;
  mutable bytes_written: int;
  mutable last_error: (exn * float) option;
  latencies: float Queue.t;  (* Keep last 1000 latencies *)
  mutable p50: float;
  mutable p95: float;
}

type t = {
  mutable sinks: (string, sink_data) Hashtbl.t;
  lock: Mutex.t;
}

(** Create a new metrics tracker *)
let create () =
  { sinks = Hashtbl.create 16
  ; lock = Mutex.create () }
;;

(** Calculate percentiles from latency queue *)
let update_percentiles latencies =
  if Queue.is_empty latencies then
    (0.0, 0.0)
  else
    let arr = Queue.fold (fun acc x -> x :: acc) [] latencies |> Array.of_list in
    Array.sort Float.compare arr;
    let len = Array.length arr in
    let p50_idx = len / 2 in
    let p95_idx = (len * 95) / 100 in
    let p50 = arr.(p50_idx) in
    let p95 = if p95_idx < len then arr.(p95_idx) else arr.(len - 1) in
    (p50, p95)
;;

(** Get or create sink data *)
let get_sink_data t sink_id =
  Mutex.lock t.lock;
  let data =
    match Hashtbl.find_opt t.sinks sink_id with
    | Some d -> d
    | None ->
        let d = {
          events_total = 0;
          events_dropped = 0;
          events_failed = 0;
          bytes_written = 0;
          last_error = None;
          latencies = Queue.create ();
          p50 = 0.0;
          p95 = 0.0;
        } in
        Hashtbl.add t.sinks sink_id d;
        d
  in
  Mutex.unlock t.lock;
  data
;;

(** Record successful event emission *)
let record_event t ~sink_id ~latency_us =
  let data = get_sink_data t sink_id in
  Mutex.lock t.lock;
  data.events_total <- data.events_total + 1;
  
  (* Keep only last 1000 latencies *)
  if Queue.length data.latencies >= 1000 then
    let _ = Queue.take data.latencies in ();
  Queue.add latency_us data.latencies;
  
  (* Update percentiles *)
  let (p50, p95) = update_percentiles data.latencies in
  data.p50 <- p50;
  data.p95 <- p95;
  
  Mutex.unlock t.lock
;;

(** Record a dropped event *)
let record_drop t ~sink_id =
  let data = get_sink_data t sink_id in
  Mutex.lock t.lock;
  data.events_dropped <- data.events_dropped + 1;
  Mutex.unlock t.lock
;;

(** Record an emission error *)
let record_error t ~sink_id exn =
  let data = get_sink_data t sink_id in
  Mutex.lock t.lock;
  data.events_failed <- data.events_failed + 1;
  data.last_error <- Some (exn, Unix.gettimeofday ());
  Mutex.unlock t.lock
;;

(** Get metrics for a specific sink *)
let get_sink_metrics t sink_id =
  Mutex.lock t.lock;
  let result =
    match Hashtbl.find_opt t.sinks sink_id with
    | None -> None
    | Some data ->
        Some {
          sink_id;
          events_total = data.events_total;
          events_dropped = data.events_dropped;
          events_failed = data.events_failed;
          bytes_written = data.bytes_written;
          last_error = data.last_error;
          latency_p50_us = data.p50;
          latency_p95_us = data.p95;
        }
  in
  Mutex.unlock t.lock;
  result
;;

(** Get metrics for all sinks *)
let get_all_metrics t =
  Mutex.lock t.lock;
  let metrics = Hashtbl.fold (fun sink_id data acc ->
    let m = {
      sink_id;
      events_total = data.events_total;
      events_dropped = data.events_dropped;
      events_failed = data.events_failed;
      bytes_written = data.bytes_written;
      last_error = data.last_error;
      latency_p50_us = data.p50;
      latency_p95_us = data.p95;
    } in
    m :: acc
  ) t.sinks [] in
  Mutex.unlock t.lock;
  metrics
;;

(** Reset all metrics *)
let reset t =
  Mutex.lock t.lock;
  Hashtbl.clear t.sinks;
  Mutex.unlock t.lock
;;

(** Export metrics as JSON *)
let to_json t =
  let all_metrics = get_all_metrics t in
  let json_metrics = 
    List.map (fun (metrics : sink_metrics) ->
      let error_json = match metrics.last_error with
        | None -> `Null
        | Some (exn, timestamp) ->
            `Assoc [
              ("exception", `String (Printexc.to_string exn));
              ("timestamp", `Float timestamp);
            ]
      in
      `Assoc [
        ("sink_id", `String metrics.sink_id);
        ("events_total", `Int metrics.events_total);
        ("events_dropped", `Int metrics.events_dropped);
        ("events_failed", `Int metrics.events_failed);
        ("bytes_written", `Int metrics.bytes_written);
        ("last_error", error_json);
        ("latency_p50_us", `Float metrics.latency_p50_us);
        ("latency_p95_us", `Float metrics.latency_p95_us);
      ]
    ) all_metrics 
  in
  `Assoc [
    ("timestamp", `Float (Unix.gettimeofday ()));
    ("sinks", `List json_metrics);
  ]
;;
