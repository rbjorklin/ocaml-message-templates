(** Tests for async_sink_queue module *)

open Alcotest
open Message_templates

(** Helper: mock sink that collects events *)
let create_mock_sink () =
  let events = ref [] in
  let emit event = events := event :: !events in
  (emit, events)

(** Test: Basic enqueue works *)
let test_enqueue_single () =
  let emit_fn, events = create_mock_sink () in
  let queue = Async_sink_queue.create Async_sink_queue.default_config emit_fn in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  Async_sink_queue.enqueue queue event;
  check int "Queue has 1 event" 1 (Async_sink_queue.get_queue_depth queue);
  Async_sink_queue.close queue;
  check int "Events flushed to sink" 1 (List.length !events)
;;

(** Test: Multiple enqueues *)
let test_enqueue_multiple () =
  let emit_fn, events = create_mock_sink () in
  let queue = Async_sink_queue.create Async_sink_queue.default_config emit_fn in
  for _i = 1 to 10 do
    let event =
      Log_event.create ~level:Level.Information
        ~message_template:"Message"
        ~rendered_message:"Message"
        ~properties:[] ()
    in
    Async_sink_queue.enqueue queue event
  done;
  check int "Queue has 10 events" 10 (Async_sink_queue.get_queue_depth queue);
  Async_sink_queue.close queue;
  check int "All 10 events flushed" 10 (List.length !events)
;;

(** Test: Queue drops oldest when full *)
let test_enqueue_drops_when_full () =
  let emit_fn, _events = create_mock_sink () in
  let config =
    { Async_sink_queue.default_config with max_queue_size= 3; flush_interval_ms= 10000 }
  in
  let queue = Async_sink_queue.create config emit_fn in
  
  (* Add 5 events to a queue of size 3 *)
  for _i = 1 to 5 do
    let event =
      Log_event.create ~level:Level.Information
        ~message_template:"Msg"
        ~rendered_message:"Msg"
        ~properties:[] ()
    in
    Async_sink_queue.enqueue queue event
  done;
  
  (* Queue should have max 3 events *)
  check int "Queue at max size" 3 (Async_sink_queue.get_queue_depth queue);
  
  let stats = Async_sink_queue.get_stats queue in
  check int "2 events dropped" 2 stats.total_dropped;
  
  Async_sink_queue.close queue
;;

(** Test: Flush empties queue *)
let test_flush_empties_queue () =
  let emit_fn, events = create_mock_sink () in
  let config = {Async_sink_queue.default_config with flush_interval_ms= 100000} in
  let queue = Async_sink_queue.create config emit_fn in
  
  for _i = 1 to 5 do
    let event =
      Log_event.create ~level:Level.Information ~message_template:"Test"
        ~rendered_message:"Test" ~properties:[] ()
    in
    Async_sink_queue.enqueue queue event
  done;
  
  check int "Queue has 5 before flush" 5 (Async_sink_queue.get_queue_depth queue);
  Async_sink_queue.flush queue;
  check int "Queue empty after flush" 0 (Async_sink_queue.get_queue_depth queue);
  check int "All 5 events emitted" 5 (List.length !events);
  
  Async_sink_queue.close queue
;;

(** Test: Background thread flushes periodically *)
let test_background_flush () =
  let emit_fn, events = create_mock_sink () in
  let config = {Async_sink_queue.default_config with flush_interval_ms= 100} in
  let queue = Async_sink_queue.create config emit_fn in
  
  for _i = 1 to 3 do
    let event =
      Log_event.create ~level:Level.Information ~message_template:"Test"
        ~rendered_message:"Test" ~properties:[] ()
    in
    Async_sink_queue.enqueue queue event
  done;
  
  (* Wait for background flush *)
  Thread.delay 0.3;
  
  (* Should have been flushed by background thread *)
  check int "Events flushed by background" 3 (List.length !events);
  
  Async_sink_queue.close queue
;;

(** Test: Error in sink doesn't crash queue *)
let test_error_handling () =
  let call_count = ref 0 in
  let emit_fn _event =
    incr call_count;
    if !call_count = 2 then raise (Failure "Sink error")
  in
  let error_caught = ref false in
  let config =
    { Async_sink_queue.default_config with
      flush_interval_ms= 100000
    ; error_handler= (fun _ -> error_caught := true)
    }
  in
  let queue = Async_sink_queue.create config emit_fn in
  
  for _i = 1 to 3 do
    let event =
      Log_event.create ~level:Level.Information ~message_template:"Test"
        ~rendered_message:"Test" ~properties:[] ()
    in
    Async_sink_queue.enqueue queue event
  done;
  
  (* Flush will encounter error on 2nd event *)
  Async_sink_queue.flush queue;
  
  (* Should still have processed other events *)
  check int "Called 3 times despite error" 3 !call_count;
  check bool "Error handler called" true !error_caught;
  
  Async_sink_queue.close queue
;;

(** Test: Queue stats are accurate *)
let test_queue_stats () =
  let emit_fn, _events = create_mock_sink () in
  let config = {Async_sink_queue.default_config with max_queue_size= 5} in
  let queue = Async_sink_queue.create config emit_fn in
  
  (* Enqueue 7 events (2 will be dropped) *)
  for _i = 1 to 7 do
    let event =
      Log_event.create ~level:Level.Information ~message_template:"Test"
        ~rendered_message:"Test" ~properties:[] ()
    in
    Async_sink_queue.enqueue queue event
  done;
  
  let stats = Async_sink_queue.get_stats queue in
  check int "Total enqueued: 7" 7 stats.total_enqueued;
  check int "Total dropped: 2" 2 stats.total_dropped;
  
  Async_sink_queue.close queue;
  
  let final_stats = Async_sink_queue.get_stats queue in
  check int "Final emitted: 5" 5 final_stats.total_emitted
;;

(** Test: Close flushes pending events *)
let test_close_flushes () =
  let emit_fn, events = create_mock_sink () in
  let config = {Async_sink_queue.default_config with flush_interval_ms= 100000} in
  let queue = Async_sink_queue.create config emit_fn in
  
  for _i = 1 to 5 do
    let event =
      Log_event.create ~level:Level.Information ~message_template:"Test"
        ~rendered_message:"Test" ~properties:[] ()
    in
    Async_sink_queue.enqueue queue event
  done;
  
  check int "Queue has pending before close" 5 (Async_sink_queue.get_queue_depth queue);
  Async_sink_queue.close queue;
  check int "Queue empty after close" 0 (Async_sink_queue.get_queue_depth queue);
  check int "All events flushed on close" 5 (List.length !events)
;;

(** Test: Concurrent enqueue/flush is thread-safe *)
let test_concurrent_access () =
  let emit_fn, _events = create_mock_sink () in
  let config = {Async_sink_queue.default_config with batch_size= 10} in
  let queue = Async_sink_queue.create config emit_fn in
  
  let enqueue_thread = Thread.create (fun () ->
    for _i = 1 to 100 do
      let event =
        Log_event.create ~level:Level.Information ~message_template:"Test"
          ~rendered_message:"Test" ~properties:[] ()
      in
      Async_sink_queue.enqueue queue event
    done
  ) () in
  
  let flush_thread = Thread.create (fun () ->
    for _i = 1 to 20 do
      Thread.delay 0.01;
      Async_sink_queue.flush queue
    done
  ) () in
  
  Thread.join enqueue_thread;
  Thread.join flush_thread;
  
  Async_sink_queue.close queue;
  
  (* All events should be accounted for *)
  let final_stats = Async_sink_queue.get_stats queue in
  check int "All 100 enqueued accounted for"
    100
    (final_stats.total_emitted + final_stats.total_dropped)
;;

let () =
  run "Async Sink Queue Tests"
    [ ( "enqueue"
      , [ test_case "Single enqueue" `Quick test_enqueue_single
        ; test_case "Multiple enqueues" `Quick test_enqueue_multiple
        ; test_case "Drop when full" `Quick test_enqueue_drops_when_full
        ] )
    ; ( "flush"
      , [ test_case "Flush empties queue" `Quick test_flush_empties_queue
        ; test_case "Background thread flushes" `Quick test_background_flush
        ; test_case "Close flushes pending" `Quick test_close_flushes
        ] )
    ; ( "reliability"
      , [ test_case "Error handling" `Quick test_error_handling
        ; test_case "Queue stats" `Quick test_queue_stats
        ; test_case "Concurrent access" `Quick test_concurrent_access
        ] )
    ]
