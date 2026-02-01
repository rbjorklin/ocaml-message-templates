(** Performance benchmarks for Message Templates *)

let iterations = 1_000_000

let timeit name f =
  let start = Unix.gettimeofday () in
  for _ = 1 to iterations do
    ignore (f ())
  done;
  let elapsed = Unix.gettimeofday () -. start in
  let ops_per_sec = float_of_int iterations /. elapsed in
  Printf.printf "%s: %.3f seconds (%.0f ops/sec)\n" name elapsed ops_per_sec

(* Benchmark 1: Simple string template with PPX *)
let benchmark_ppx_simple () =
  let username = "alice" in
  let ip = "192.168.1.1" in
  fun () ->
    let msg, _ = [%template "User {username} logged in from {ip}"] in
    msg

(* Benchmark 2: Printf equivalent (baseline) *)
let benchmark_printf_simple () =
  let username = "alice" in
  let ip = "192.168.1.1" in
  fun () ->
    Printf.sprintf "User %s logged in from %s" username ip

(* Benchmark 3: String concatenation (theoretical max) *)
let benchmark_string_concat () =
  let username = "alice" in
  let ip = "192.168.1.1" in
  fun () ->
    "User " ^ username ^ " logged in from " ^ ip

(* Benchmark 4: Multiple variables with format specifiers *)
let benchmark_ppx_formats () =
  let count = 42 in
  let score = 98.5 in
  let active = true in
  fun () ->
    let msg, _ = [%template "Count: {count:d}, Score: {score:f}, Active: {active:B}"] in
    msg

(* Benchmark 5: Printf equivalent with formats *)
let benchmark_printf_formats () =
  let count = 42 in
  let score = 98.5 in
  let active = true in
  fun () ->
    Printf.sprintf "Count: %d, Score: %f, Active: %B" count score active

(* Benchmark 6: JSON output generation *)
let benchmark_ppx_json () =
  let user = "bob" in
  let action = "login" in
  fun () ->
    let _, json = [%template "User {user} performed {action}"] in
    Yojson.Safe.to_string json

let () =
  Printf.printf "Message Templates - Performance Benchmarks\n";
  Printf.printf "==========================================\n";
  Printf.printf "Iterations per test: %d\n\n" iterations;
  
  timeit "PPX Simple Template" (benchmark_ppx_simple ());
  timeit "Printf Simple" (benchmark_printf_simple ());
  timeit "String Concat" (benchmark_string_concat ());
  
  Printf.printf "\n";
  
  timeit "PPX with Formats" (benchmark_ppx_formats ());
  timeit "Printf with Formats" (benchmark_printf_formats ());
  
  Printf.printf "\n";
  
  timeit "PPX JSON Output" (benchmark_ppx_json ());
  
  Printf.printf "\nBenchmark complete!\n"
