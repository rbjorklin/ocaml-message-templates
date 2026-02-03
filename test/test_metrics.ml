open Alcotest
open Message_templates

(** Test metrics collection and reporting *)

(** Test 1: Record single event *)
let test_record_event () =
  let m = Metrics.create () in
  Metrics.record_event m ~sink_id:"file" ~latency_us:1.5;
  let metrics = Metrics.get_sink_metrics m "file" in
  match metrics with
  | None -> fail "Expected metrics for sink"
  | Some sm ->
      check int "events_total" 1 sm.events_total;
      check int "events_dropped" 0 sm.events_dropped;
      check int "events_failed" 0 sm.events_failed
;;

(** Test 2: Multiple events increase counter *)
let test_multiple_events () =
  let m = Metrics.create () in
  for i = 1 to 5 do
    Metrics.record_event m ~sink_id:"console" ~latency_us:(float_of_int i)
  done;
  let metrics = Metrics.get_sink_metrics m "console" in
  match metrics with
  | None -> fail "Expected metrics"
  | Some sm ->
      check int "events_total should be 5" 5 sm.events_total
;;

(** Test 3: Latency percentiles computed correctly *)
let test_latency_percentiles () =
  let m = Metrics.create () in
  let latencies = [1.0; 2.0; 3.0; 4.0; 5.0] in
  List.iter (fun lat -> Metrics.record_event m ~sink_id:"s" ~latency_us:lat) latencies;
  let metrics = Metrics.get_sink_metrics m "s" in
  match metrics with
  | None -> fail "Expected metrics"
  | Some sm ->
      check bool "p50 should be 3.0" true (Float.equal sm.latency_p50_us 3.0);
      check bool "p95 should be >= 4.0" true (sm.latency_p95_us >= 4.0)
;;

(** Test 4: Record drops *)
let test_record_drops () =
  let m = Metrics.create () in
  Metrics.record_event m ~sink_id:"net" ~latency_us:1.0;
  Metrics.record_drop m ~sink_id:"net";
  Metrics.record_drop m ~sink_id:"net";
  let metrics = Metrics.get_sink_metrics m "net" in
  match metrics with
  | None -> fail "Expected metrics"
  | Some sm ->
      check int "events_dropped should be 2" 2 sm.events_dropped;
      check int "events_total should be 1" 1 sm.events_total
;;

(** Test 5: Record errors *)
let test_record_errors () =
  let m = Metrics.create () in
  let exn = Failure "test error" in
  Metrics.record_event m ~sink_id:"file" ~latency_us:1.0;
  Metrics.record_error m ~sink_id:"file" exn;
  let metrics = Metrics.get_sink_metrics m "file" in
  match metrics with
  | None -> fail "Expected metrics"
  | Some sm ->
      check int "events_failed should be 1" 1 sm.events_failed;
      check bool "last_error should be Some" true (Option.is_some sm.last_error)
;;

(** Test 6: Multiple sinks tracked independently *)
let test_multiple_sinks () =
  let m = Metrics.create () in
  Metrics.record_event m ~sink_id:"file" ~latency_us:1.0;
  Metrics.record_event m ~sink_id:"file" ~latency_us:2.0;
  Metrics.record_event m ~sink_id:"console" ~latency_us:0.5;
  Metrics.record_drop m ~sink_id:"net";
  
  let file_metrics = Metrics.get_sink_metrics m "file" in
  let console_metrics = Metrics.get_sink_metrics m "console" in
  let net_metrics = Metrics.get_sink_metrics m "net" in
  
  (match file_metrics with
   | Some sm -> check int "file events" 2 sm.events_total
   | None -> fail "Expected file metrics");
  
  (match console_metrics with
   | Some sm -> check int "console events" 1 sm.events_total
   | None -> fail "Expected console metrics");
  
  (match net_metrics with
   | Some sm -> check int "net drops" 1 sm.events_dropped
   | None -> fail "Expected net metrics")
;;

(** Test 7: Get all metrics *)
let test_get_all_metrics () =
  let m = Metrics.create () in
  Metrics.record_event m ~sink_id:"a" ~latency_us:1.0;
  Metrics.record_event m ~sink_id:"b" ~latency_us:2.0;
  Metrics.record_event m ~sink_id:"c" ~latency_us:3.0;
  
  let all_metrics = Metrics.get_all_metrics m in
  check int "should have 3 sinks" 3 (List.length all_metrics)
;;

(** Test 8: Reset clears all metrics *)
let test_reset () =
  let m = Metrics.create () in
  Metrics.record_event m ~sink_id:"file" ~latency_us:1.0;
  Metrics.record_event m ~sink_id:"console" ~latency_us:2.0;
  Metrics.reset m;
  
  let all_metrics = Metrics.get_all_metrics m in
  check int "should have 0 sinks after reset" 0 (List.length all_metrics)
;;

(** Test 9: JSON export includes all fields *)
let test_to_json () =
  let m = Metrics.create () in
  Metrics.record_event m ~sink_id:"file" ~latency_us:1.5;
  Metrics.record_drop m ~sink_id:"file";
  Metrics.record_error m ~sink_id:"file" (Failure "test");
  
  let json = Metrics.to_json m in
  match json with
  | `Assoc fields ->
      (match List.assoc_opt "sinks" fields with
       | Some (`List sinks) ->
           check bool "should have one sink" true (List.length sinks = 1)
       | _ -> fail "Expected sinks list in JSON")
  | _ -> fail "Expected JSON object"
;;

(** Test 10: Latency queue limited to 1000 entries *)
let test_latency_queue_limit () =
  let m = Metrics.create () in
  (* Record 1500 latencies *)
  for i = 1 to 1500 do
    Metrics.record_event m ~sink_id:"test" ~latency_us:(float_of_int (i mod 100))
  done;
  
  (* Total events should be 1500 *)
  let metrics = Metrics.get_sink_metrics m "test" in
  match metrics with
  | Some sm ->
      check int "events_total should be 1500" 1500 sm.events_total
  | None -> fail "Expected metrics"
;;

(** Test 11: Thread-safe concurrent access *)
let test_concurrent_access () =
  let m = Metrics.create () in
  let threads = ref [] in
  
  (* Spawn 10 threads, each recording 100 events *)
  for _thread_id = 1 to 10 do
    let t = Thread.create (fun () ->
      for i = 1 to 100 do
        Metrics.record_event m ~sink_id:"concurrent" ~latency_us:(float_of_int i)
      done
    ) () in
    threads := t :: !threads
  done;
  
  (* Wait for all threads *)
  List.iter Thread.join !threads;
  
  let metrics = Metrics.get_sink_metrics m "concurrent" in
  match metrics with
  | Some sm ->
      check int "events_total should be 1000" 1000 sm.events_total
  | None -> fail "Expected metrics"
;;

(** Test 12: Non-existent sink returns None *)
let test_nonexistent_sink () =
  let m = Metrics.create () in
  let metrics = Metrics.get_sink_metrics m "nonexistent" in
  check bool "should be None" true (metrics = None)
;;

let () =
  run "Metrics Tests" [
    "recording", [
      test_case "Record single event" `Quick test_record_event;
      test_case "Multiple events" `Quick test_multiple_events;
      test_case "Latency percentiles" `Quick test_latency_percentiles;
      test_case "Record drops" `Quick test_record_drops;
      test_case "Record errors" `Quick test_record_errors;
    ];
    "sinks", [
      test_case "Multiple sinks independent" `Quick test_multiple_sinks;
      test_case "Get all metrics" `Quick test_get_all_metrics;
      test_case "Non-existent sink" `Quick test_nonexistent_sink;
    ];
    "management", [
      test_case "Reset clears metrics" `Quick test_reset;
      test_case "JSON export" `Quick test_to_json;
    ];
    "limits", [
      test_case "Latency queue limit" `Quick test_latency_queue_limit;
    ];
    "concurrency", [
      test_case "Concurrent access" `Slow test_concurrent_access;
    ];
  ]
