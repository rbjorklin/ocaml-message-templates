(** Tests for circuit breaker module *)

open Alcotest
open Message_templates

let test_create () =
  let cb =
    Circuit_breaker.create ~failure_threshold:3 ~reset_timeout_ms:1000 ()
  in
  check bool "initial state should be Closed" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Closed)
;;

let test_invalid_config () =
  check_raises "failure_threshold must be positive"
    (Invalid_argument "failure_threshold must be positive") (fun () ->
      ignore
        (Circuit_breaker.create ~failure_threshold:0 ~reset_timeout_ms:1000 ()) );
  check_raises "reset_timeout_ms must be positive"
    (Invalid_argument "reset_timeout_ms must be positive") (fun () ->
      ignore
        (Circuit_breaker.create ~failure_threshold:1 ~reset_timeout_ms:0 ()) )
;;

let test_successful_call () =
  let cb =
    Circuit_breaker.create ~failure_threshold:3 ~reset_timeout_ms:1000 ()
  in
  let result = Circuit_breaker.call cb (fun () -> 42) in
  check (option int) "successful call returns Some" (Some 42) result
;;

let test_failure_opens_circuit () =
  let cb =
    Circuit_breaker.create ~failure_threshold:2 ~reset_timeout_ms:5000 ()
  in
  (* First failure *)
  let r1 = Circuit_breaker.call cb (fun () -> raise (Failure "error")) in
  check (option int) "first failure returns None" None r1;
  check bool "still Closed after 1 failure" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Closed);

  (* Second failure - should open circuit *)
  let r2 = Circuit_breaker.call cb (fun () -> raise (Failure "error")) in
  check (option int) "second failure returns None" None r2;
  check bool "Open after 2 failures" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Open)
;;

let test_open_circuit_rejects_calls () =
  let cb =
    Circuit_breaker.create ~failure_threshold:1 ~reset_timeout_ms:5000 ()
  in
  (* Open the circuit *)
  ignore (Circuit_breaker.call cb (fun () -> raise (Failure "error")));
  check bool "circuit is Open" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Open);

  (* Subsequent calls should fail fast *)
  let r = Circuit_breaker.call cb (fun () -> 42) in
  check (option int) "call returns None when open" None r
;;

let test_half_open_after_timeout () =
  let cb =
    Circuit_breaker.create ~failure_threshold:1 ~reset_timeout_ms:50 ()
  in
  (* Open the circuit *)
  ignore (Circuit_breaker.call cb (fun () -> raise (Failure "error")));
  check bool "circuit is Open" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Open);

  (* Wait for reset timeout *)
  Thread.delay 0.1;

  (* Should be Half_open now *)
  check bool "circuit is Half_open after timeout" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Half_open)
;;

let test_half_open_success_closes_circuit () =
  let cb =
    Circuit_breaker.create ~failure_threshold:1 ~reset_timeout_ms:50 ()
  in
  (* Open the circuit *)
  ignore (Circuit_breaker.call cb (fun () -> raise (Failure "error")));
  Thread.delay 0.1;

  (* Should be Half_open, successful call should close it *)
  let r = Circuit_breaker.call cb (fun () -> 42) in
  check (option int) "successful call returns Some" (Some 42) r;
  check bool "circuit is Closed after success" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Closed)
;;

let test_half_open_failure_reopens_circuit () =
  let cb =
    Circuit_breaker.create ~failure_threshold:1 ~reset_timeout_ms:50 ()
  in
  (* Open the circuit *)
  ignore (Circuit_breaker.call cb (fun () -> raise (Failure "error")));
  Thread.delay 0.1;

  (* Should be Half_open, failing call should reopen it *)
  let r = Circuit_breaker.call cb (fun () -> raise (Failure "error")) in
  check (option int) "failure returns None" None r;
  check bool "circuit is Open after failure" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Open)
;;

let test_reset () =
  let cb =
    Circuit_breaker.create ~failure_threshold:1 ~reset_timeout_ms:5000 ()
  in
  (* Open the circuit *)
  ignore (Circuit_breaker.call cb (fun () -> raise (Failure "error")));
  check bool "circuit is Open" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Open);

  (* Reset it *)
  Circuit_breaker.reset cb;
  check bool "circuit is Closed after reset" true
    (Circuit_breaker.get_state cb = Circuit_breaker.Closed);

  (* Should work normally *)
  let r = Circuit_breaker.call cb (fun () -> 42) in
  check (option int) "call works after reset" (Some 42) r
;;

let test_stats () =
  let cb =
    Circuit_breaker.create ~failure_threshold:3 ~reset_timeout_ms:1000 ()
  in

  (* Initial stats *)
  let s1 = Circuit_breaker.get_stats cb in
  check int "initial failures = 0" 0 s1.failure_count;
  check int "initial successes = 0" 0 s1.success_count;

  (* Some failures *)
  ignore (Circuit_breaker.call cb (fun () -> raise (Failure "err")));
  ignore (Circuit_breaker.call cb (fun () -> raise (Failure "err")));
  let s2 = Circuit_breaker.get_stats cb in
  check int "failures = 2" 2 s2.failure_count;

  (* Some successes *)
  ignore (Circuit_breaker.call cb (fun () -> 1));
  ignore (Circuit_breaker.call cb (fun () -> 2));
  let s3 = Circuit_breaker.get_stats cb in
  check int "successes = 2" 2 s3.success_count;

  (* Reset clears stats *)
  Circuit_breaker.reset cb;
  let s4 = Circuit_breaker.get_stats cb in
  check int "failures cleared after reset" 0 s4.failure_count
;;

let () =
  run "Circuit Breaker Tests"
    [ ( "create"
      , [ test_case "Create circuit breaker" `Quick test_create
        ; test_case "Invalid config" `Quick test_invalid_config ] )
    ; ( "operation"
      , [ test_case "Successful call" `Quick test_successful_call
        ; test_case "Failure opens circuit" `Quick test_failure_opens_circuit
        ; test_case "Open circuit rejects calls" `Quick
            test_open_circuit_rejects_calls
        ; test_case "Half open after timeout" `Quick
            test_half_open_after_timeout
        ; test_case "Half open success closes circuit" `Quick
            test_half_open_success_closes_circuit
        ; test_case "Half open failure reopens circuit" `Quick
            test_half_open_failure_reopens_circuit
        ; test_case "Reset" `Quick test_reset
        ; test_case "Stats tracking" `Quick test_stats ] ) ]
;;
