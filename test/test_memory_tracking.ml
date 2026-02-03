(** Tests for memory tracking module *)

open Alcotest
open Message_templates

let test_create () =
  let config = Memory_tracking.default_config in
  let tracker = Memory_tracking.create config in
  check int "initial usage is 0" 0 (Memory_tracking.get_usage tracker);
  check bool "initially not over limit" false
    (Memory_tracking.is_over_limit tracker)
;;

let test_invalid_config () =
  check_raises "max_queue_bytes must be positive"
    (Invalid_argument "max_queue_bytes must be positive") (fun () ->
      ignore
        (Memory_tracking.create
           {Memory_tracking.default_config with max_queue_bytes= 0} ) );
  check_raises "max_event_size_bytes must be positive"
    (Invalid_argument "max_event_size_bytes must be positive") (fun () ->
      ignore
        (Memory_tracking.create
           {Memory_tracking.default_config with max_event_size_bytes= 0} ) )
;;

let test_record_enqueue () =
  let config = {Memory_tracking.default_config with max_queue_bytes= 1000} in
  let tracker = Memory_tracking.create config in

  Memory_tracking.record_enqueue tracker ~bytes:100;
  check int "usage is 100" 100 (Memory_tracking.get_usage tracker);

  Memory_tracking.record_enqueue tracker ~bytes:200;
  check int "usage is 300" 300 (Memory_tracking.get_usage tracker)
;;

let test_record_dequeue () =
  let config = {Memory_tracking.default_config with max_queue_bytes= 1000} in
  let tracker = Memory_tracking.create config in

  Memory_tracking.record_enqueue tracker ~bytes:500;
  check int "usage is 500" 500 (Memory_tracking.get_usage tracker);

  Memory_tracking.record_dequeue tracker ~bytes:200;
  check int "usage is 300" 300 (Memory_tracking.get_usage tracker);

  Memory_tracking.record_dequeue tracker ~bytes:500;
  (* More than current *)
  check int "usage doesn't go below 0" 0 (Memory_tracking.get_usage tracker)
;;

let test_is_over_limit () =
  let limit_exceeded = ref false in
  let config =
    { Memory_tracking.default_config with
      max_queue_bytes= 100
    ; on_limit_exceeded= (fun () -> limit_exceeded := true) }
  in
  let tracker = Memory_tracking.create config in

  check bool "not over limit initially" false
    (Memory_tracking.is_over_limit tracker);

  Memory_tracking.record_enqueue tracker ~bytes:50;
  check bool "not over limit at 50" false
    (Memory_tracking.is_over_limit tracker);
  check bool "limit not exceeded" false !limit_exceeded;

  Memory_tracking.record_enqueue tracker ~bytes:60;
  (* Total 110 > 100 *)
  check bool "over limit at 110" true (Memory_tracking.is_over_limit tracker);
  check bool "limit exceeded callback called" true !limit_exceeded
;;

let test_event_size_limit () =
  let config =
    {Memory_tracking.default_config with max_event_size_bytes= 100}
  in
  let tracker = Memory_tracking.create config in

  (* Small event should work *)
  Memory_tracking.record_enqueue tracker ~bytes:50;
  check int "usage is 50" 50 (Memory_tracking.get_usage tracker);

  (* Large event should raise *)
  check_raises "event too large"
    (Invalid_argument "Event size 200 exceeds max_event_size_bytes 100")
    (fun () -> Memory_tracking.record_enqueue tracker ~bytes:200 )
;;

let test_set_config () =
  let limit_exceeded = ref false in
  let config =
    { Memory_tracking.default_config with
      max_queue_bytes= 1000
    ; on_limit_exceeded= (fun () -> limit_exceeded := true) }
  in
  let tracker = Memory_tracking.create config in

  Memory_tracking.record_enqueue tracker ~bytes:500;
  check bool "not over limit with 500/1000" false
    (Memory_tracking.is_over_limit tracker);

  (* Lower the limit *)
  Memory_tracking.set_config tracker {config with max_queue_bytes= 400};
  check bool "over limit with 500/400" true
    (Memory_tracking.is_over_limit tracker);
  check bool "callback called when lowering limit" true !limit_exceeded
;;

let test_get_config () =
  let config =
    { Memory_tracking.default_config with
      max_queue_bytes= 5000
    ; max_event_size_bytes= 1000 }
  in
  let tracker = Memory_tracking.create config in
  let retrieved = Memory_tracking.get_config tracker in
  check int "max_queue_bytes matches" 5000 retrieved.max_queue_bytes;
  check int "max_event_size_bytes matches" 1000 retrieved.max_event_size_bytes
;;

let test_trim_to_limit () =
  let limit_exceeded = ref false in
  let config =
    { Memory_tracking.default_config with
      max_queue_bytes= 100
    ; on_limit_exceeded= (fun () -> limit_exceeded := true) }
  in
  let tracker = Memory_tracking.create config in

  Memory_tracking.record_enqueue tracker ~bytes:150;
  limit_exceeded := false;

  (* Reset *)
  Memory_tracking.trim_to_limit tracker;
  check bool "callback called on trim" true !limit_exceeded
;;

let test_concurrent_access () =
  let config = {Memory_tracking.default_config with max_queue_bytes= 10000} in
  let tracker = Memory_tracking.create config in

  (* Spawn multiple threads enqueuing *)
  let threads =
    List.init 10 (fun _ ->
        Thread.create
          (fun () ->
            for i = 1 to 100 do
              Memory_tracking.record_enqueue tracker ~bytes:1;
              if i mod 2 = 0 then
                Memory_tracking.record_dequeue tracker ~bytes:1
            done )
          () )
  in

  List.iter Thread.join threads;

  (* Should have 500 bytes (10 threads * 100 iterations / 2) *)
  check int "final usage correct" 500 (Memory_tracking.get_usage tracker)
;;

let () =
  run "Memory Tracking Tests"
    [ ( "create"
      , [ test_case "Create tracker" `Quick test_create
        ; test_case "Invalid config" `Quick test_invalid_config ] )
    ; ( "operations"
      , [ test_case "Record enqueue" `Quick test_record_enqueue
        ; test_case "Record dequeue" `Quick test_record_dequeue
        ; test_case "Is over limit" `Quick test_is_over_limit
        ; test_case "Event size limit" `Quick test_event_size_limit
        ; test_case "Set config" `Quick test_set_config
        ; test_case "Get config" `Quick test_get_config
        ; test_case "Trim to limit" `Quick test_trim_to_limit
        ; test_case "Concurrent access" `Quick test_concurrent_access ] ) ]
;;
