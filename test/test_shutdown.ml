(** Tests for shutdown module *)

open Alcotest
open Message_templates

let test_create () =
  let shutdown = Shutdown.create () in
  check bool "is_shutdown should be false initially" false
    (Shutdown.is_shutdown shutdown)
;;

let test_register_and_execute_immediate () =
  let shutdown = Shutdown.create () in
  let called = ref false in
  Shutdown.register shutdown (fun () -> called := true);
  Shutdown.execute shutdown Immediate;
  check bool "handler should be called" true !called;
  check bool "is_shutdown should be true after execute" true
    (Shutdown.is_shutdown shutdown)
;;

let test_register_order_lifo () =
  let shutdown = Shutdown.create () in
  let order = ref [] in
  Shutdown.register shutdown (fun () -> order := 1 :: !order);
  Shutdown.register shutdown (fun () -> order := 2 :: !order);
  Shutdown.register shutdown (fun () -> order := 3 :: !order);
  Shutdown.execute shutdown Immediate;
  check (list int) "handlers should execute in LIFO order" [3; 2; 1] !order
;;

let test_execute_twice_raises () =
  let shutdown = Shutdown.create () in
  Shutdown.execute shutdown Immediate;
  check_raises "execute twice should raise" (Failure "Shutdown already executed")
    (fun () -> Shutdown.execute shutdown Immediate )
;;

let test_flush_pending () =
  let shutdown = Shutdown.create () in
  let called = ref 0 in
  Shutdown.register shutdown (fun () -> Thread.delay 0.01; incr called);
  Shutdown.register shutdown (fun () -> Thread.delay 0.01; incr called);
  let start = Unix.gettimeofday () in
  Shutdown.execute shutdown Flush_pending;
  let elapsed = Unix.gettimeofday () -. start in
  check int "both handlers should be called" 2 !called;
  (* Both run concurrently, should take ~10ms not ~20ms *)
  check bool "should complete quickly" true (elapsed < 0.03)
;;

let test_graceful_timeout () =
  let shutdown = Shutdown.create () in
  let called = ref false in
  Shutdown.register shutdown (fun () -> called := true);
  Shutdown.execute shutdown (Graceful 5.0);
  check bool "handler should be called" true !called
;;

let test_graceful_with_slow_handler () =
  let shutdown = Shutdown.create () in
  let called = ref false in
  Shutdown.register shutdown (fun () ->
      Thread.delay 0.05;
      (* 50ms delay *)
      called := true );
  let start = Unix.gettimeofday () in
  Shutdown.execute shutdown (Graceful 0.01);
  (* 10ms timeout *)
  let elapsed = Unix.gettimeofday () -. start in
  (* Handler should have been called but with timeout warning *)
  check bool "should complete within timeout" true (elapsed < 0.1)
;;

let test_handler_error_doesnt_stop_others () =
  let shutdown = Shutdown.create () in
  let called = ref false in
  Shutdown.register shutdown (fun () -> raise (Failure "handler error"));
  Shutdown.register shutdown (fun () -> called := true);
  (* Should not raise, just log error *)
  Shutdown.execute shutdown Immediate;
  check bool "second handler should be called" true !called
;;

let test_reset () =
  let shutdown = Shutdown.create () in
  Shutdown.execute shutdown Immediate;
  check bool "is_shutdown should be true" true (Shutdown.is_shutdown shutdown);
  Shutdown.reset shutdown;
  check bool "is_shutdown should be false after reset" false
    (Shutdown.is_shutdown shutdown);
  (* Can register and execute again *)
  let called = ref false in
  Shutdown.register shutdown (fun () -> called := true);
  Shutdown.execute shutdown Immediate;
  check bool "handler should be called after reset" true !called
;;

let () =
  run "Shutdown Tests"
    [ ("create", [test_case "Create shutdown controller" `Quick test_create])
    ; ( "execute"
      , [ test_case "Register and execute immediate" `Quick
            test_register_and_execute_immediate
        ; test_case "Register order LIFO" `Quick test_register_order_lifo
        ; test_case "Execute twice raises" `Quick test_execute_twice_raises
        ; test_case "Flush pending" `Quick test_flush_pending
        ; test_case "Graceful timeout" `Quick test_graceful_timeout
        ; test_case "Graceful with slow handler" `Quick
            test_graceful_with_slow_handler
        ; test_case "Handler error doesn't stop others" `Quick
            test_handler_error_doesnt_stop_others
        ; test_case "Reset" `Quick test_reset ] ) ]
;;
