(** Circuit breaker pattern for error recovery

    The circuit breaker prevents cascade failures by temporarily blocking calls
    when failures exceed a threshold. It has three states:
    - Closed: Normal operation, calls pass through
    - Open: Failing fast, calls rejected immediately
    - Half_open: Testing if service recovered

    Example:
    {[
      let cb =
        Circuit_breaker.create ~failure_threshold:5 ~reset_timeout_ms:30000 ()
      in

      (* Protected call *)
      let success = Circuit_breaker.call cb (fun () -> risky_operation ()) in

      if not success then
        Printf.printf "Circuit is open, request rejected\n"
    ]} *)

(** Circuit breaker state *)
type state =
  | Closed
  | Open
  | Half_open

(** Circuit breaker (opaque) *)
type t

(** Create a new circuit breaker *)
val create : failure_threshold:int -> reset_timeout_ms:int -> unit -> t
(** @param failure_threshold Number of failures before opening circuit
    @param reset_timeout_ms Milliseconds to wait before trying Half_open
    @return A new circuit breaker in Closed state *)

(** Call a protected function through the circuit breaker *)
val call : t -> (unit -> 'a) -> 'a option
(** @param t The circuit breaker
    @param f Function to call if circuit is closed
    @return
      Some result if call succeeded, None if circuit is open or call failed *)

(** Get current circuit state *)
val get_state : t -> state
(** @param t The circuit breaker
    @return Current state (Closed, Open, or Half_open) *)

(** Manually reset the circuit breaker *)
val reset : t -> unit
(** Forces circuit back to Closed state.
    @param t The circuit breaker *)

(** Get failure statistics as (failure_count, current_state, last_failure_time)
*)
val get_stats : t -> int * state * float
(** @param t The circuit breaker
    @return Statistics tuple: (failure_count, current_state, last_failure_time)
*)
