# Plan 6: Add Comprehensive Test Coverage

## Status
**Priority:** MEDIUM  
**Estimated Effort:** 8-12 hours  
**Risk Level:** Low (additive changes)

## Problem Statement

Current test coverage has significant gaps:

### Missing Test Categories

1. **Multicore Domain Tests**
   - No tests for Domain.DLS usage (timestamp_cache, log_context)
   - No tests for parallel logging from multiple domains
   - Race conditions not exercised

2. **Property-Based Tests**
   - Limited use of QCheck
   - Template parsing edge cases not systematically tested
   - No fuzzing of user inputs

3. **Failure Injection**
   - Circuit breaker only tested for basic functionality
   - No disk full scenarios for file sink
   - No network failure tests (if network sinks added)

4. **Edge Cases**
   - File rolling at exact day/hour boundaries
   - Timestamp cache behavior at millisecond boundaries
   - Empty templates, very long templates
   - Unicode in templates and properties

5. **Performance Tests**
   - No regression benchmarks in CI
   - No memory leak detection
   - No contention tests for async queue

### Current Test Structure

```
test/
├── test_circuit_breaker.ml     (basic unit tests)
├── test_configuration.ml       (configuration builder)
├── test_escape.ml              (JSON escaping)
├── test_global_log.ml          (global logger)
├── test_json_sink.ml           (JSON output)
├── test_level.ml               (level comparisons)
├── test_logger.ml              (logger functionality)
├── test_metrics.ml             (metrics collection)
├── test_parser.ml              (template parsing)
├── test_phase6_async_queue.ml  (async queue)
├── test_ppx_comprehensive.ml   (PPX tests)
├── test_qcheck_*.ml            (property-based - minimal)
├── test_shutdown.ml            (shutdown behavior)
├── test_sinks.ml               (sink tests)
├── test_timestamp_cache.ml     (timestamp caching)
└── test_type_coverage.ml       (type handling)
```

## Solution

Add comprehensive test suites for missing categories:

## Implementation Steps

### Step 1: Create Multicore Test Suite

**File:** `test/test_multicore.ml`

```ocaml
(** Multicore-specific tests for domain safety *)

open Alcotest
open Message_templates

let test_timestamp_cache_domain_isolation () =
  (* Each domain should have its own timestamp cache *)
  let times = Array.make 2 None in
  
  Timestamp_cache.set_enabled true;
  
  let d1 = Domain.spawn (fun () ->
    let t1 = Timestamp_cache.get_ptime () in
    Thread.delay 0.002;  (* Wait 2ms *)
    let t2 = Timestamp_cache.get_ptime () in
    times.(0) <- Some (t1, t2))
  in
  
  let d2 = Domain.spawn (fun () ->
    let t1 = Timestamp_cache.get_ptime () in
    Thread.delay 0.002;
    let t2 = Timestamp_cache.get_ptime () in
    times.(1) <- Some (t1, t2))
  in
  
  Domain.join d1;
  Domain.join d2;
  
  (* Both domains should have advanced their timestamps *)
  (match times.(0) with
   | Some (t1, t2) ->
       check bool "domain1 time advanced" true 
         (Ptime.compare t1 t2 < 0)
   | None -> fail "domain1 didn't record times");
  
  (match times.(1) with
   | Some (t1, t2) ->
       check bool "domain2 time advanced" true
         (Ptime.compare t1 t2 < 0)
   | None -> fail "domain2 didn't record times")

let test_parallel_logging () =
  (* Multiple domains logging concurrently *)
  let path = Filename.temp_file "multicore_test" ".log" in
  let sink = create_file_sink path in
  let logger = Logger.create ~min_level:Level.Debug ~sinks:[sink] in
  
  let message_count = 1000 in
  let domain_count = 4 in
  
  let domains = List.init domain_count (fun domain_id ->
    Domain.spawn (fun () ->
      for i = 1 to message_count do
        Logger.information logger 
          (Printf.sprintf "Domain %d message %d" domain_id i)
          [("domain", `Int domain_id); ("seq", `Int i)]
      done))
  in
  
  List.iter Domain.join domains;
  Logger.close logger;
  
  (* Count messages in file *)
  let content = read_file path in
  let lines = String.split_on_char '\n' content in
  let logged_count = List.length (List.filter (fun s -> s <> "") lines) in
  
  check int "all messages logged" (message_count * domain_count) logged_count;
  
  Sys.remove path

let test_log_context_domain_isolation () =
  (* Context properties should be isolated per-domain *)
  let results = Array.make 2 [] in
  
  let d1 = Domain.spawn (fun () ->
    Log_context.with_property "key" (`String "domain1") (fun () ->
      (* Yield to allow interleaving *)
      Thread.yield ();
      results.(0) <- Log_context.current_properties ()))
  in
  
  let d2 = Domain.spawn (fun () ->
    Log_context.with_property "key" (`String "domain2") (fun () ->
      Thread.yield ();
      results.(1) <- Log_context.current_properties ()))
  in
  
  Domain.join d1;
  Domain.join d2;
  
  check (list (pair string yojson)) "domain1 context" 
    [("key", `String "domain1")] results.(0);
  check (list (pair string yojson)) "domain2 context"
    [("key", `String "domain2")] results.(1)

let test_circuit_breaker_thread_safety () =
  (* Circuit breaker from multiple threads *)
  let cb = Circuit_breaker.create ~failure_threshold:100 
    ~reset_timeout_ms:1000 () in
  
  let success_count = ref 0 in
  let failure_count = ref 0 in
  let lock = Mutex.create () in
  
  let threads = List.init 10 (fun _ ->
    Thread.create (fun () ->
      for _ = 1 to 50 do
        match Circuit_breaker.call cb (fun () -> 
          if Random.bool () then raise Exit else ()) with
        | Some () ->
            Mutex.lock lock;
            incr success_count;
            Mutex.unlock lock
        | None ->
            Mutex.lock lock;
            incr failure_count;
            Mutex.unlock lock
      done) ())
  in
  
  List.iter Thread.join threads;
  
  (* Total calls should equal success + failure + blocked *)
  let stats = Circuit_breaker.get_stats cb in
  check bool "circuit breaker handled concurrent calls" true
    (stats.failure_count >= 0)

let () =
  run "Multicore Tests"
    [ ("timestamp_cache", 
        [ test_case "domain isolation" `Quick test_timestamp_cache_domain_isolation ] )
    ; ("logging",
        [ test_case "parallel logging" `Slow test_parallel_logging ] )
    ; ("context",
        [ test_case "domain isolation" `Quick test_log_context_domain_isolation ] )
    ; ("circuit_breaker",
        [ test_case "thread safety" `Quick test_circuit_breaker_thread_safety ] )
    ]
```

### Step 2: Expand Property-Based Tests

**File:** `test/test_qcheck_templates.ml` (expand)

```ocaml
(** Property-based tests for template system *)

open QCheck
open Message_templates

(* Generator for template strings *)
let template_part_gen =
  let text_gen = 
    Gen.map (String.map (function '{' | '}' -> 'X' | c -> c))
      (Gen.string_printable) 
  in
  let hole_name_gen = 
    Gen.oneof [Gen.string_size ~gen:Gen.lowercase (Gen.int_range 1 20)]
  in
  let hole_gen = 
    Gen.map (fun name -> "{" ^ name ^ "}") hole_name_gen
  in
  Gen.oneof [text_gen; hole_gen]

let template_gen =
  Gen.map (String.concat "") 
    (Gen.list_size (Gen.int_range 0 20) template_part_gen)

(* Property: parsing never raises exception *)
let parse_never_raises =
  Test.make ~name:"parse_never_raises" ~count:10000
    template_gen
    (fun template_str ->
      match Template_parser.parse_template template_str with
      | Ok _ -> true
      | Error _ -> true)

(* Property: roundtrip reconstruction *)
let roundtrip_reconstruction =
  Test.make ~name:"roundtrip_reconstruction" ~count:5000
    (Gen.map (fun s -> "{" ^ s ^ "}") 
      (Gen.string_size ~gen:Gen.lowercase (Gen.int_range 1 30)))
    (fun template_str ->
      match Template_parser.parse_template template_str with
      | Ok parts ->
          let reconstructed = Types.reconstruct_template parts in
          reconstructed = template_str
      | Error _ -> true)

(* Property: hole extraction is consistent *)
let hole_extraction_consistent =
  Test.make ~name:"hole_extraction_consistent" ~count:5000
    template_gen
    (fun template_str ->
      match Template_parser.parse_template template_str with
      | Ok parts ->
          let holes = Template_parser.extract_holes parts in
          (* Every hole should appear in parts *)
          List.for_all (fun (hole : Types.hole) ->
            List.exists (function
              | Types.Hole h -> h.name = hole.name
              | _ -> false)
              parts)
            holes
      | Error _ -> true)

(* Property: escaped braces preserved *)
let escaped_braces_preserved =
  Test.make ~name:"escaped_braces_preserved" ~count:1000
    (Gen.map (fun s -> "{{" ^ s ^ "}}") Gen.string_printable)
    (fun template_str ->
      match Template_parser.parse_template template_str with
      | Ok [Types.Text s] -> s = "{" ^ (String.sub template_str 2 
          (String.length template_str - 4)) ^ "}"
      | _ -> false)

(* Property: JSON escaping is reversible for printable strings *)
let json_escape_roundtrip =
  Test.make ~name:"json_escape_roundtrip" ~count:5000
    Gen.string_printable
    (fun str ->
      let escaped = Log_event.escape_json_string str in
      (* Parse the escaped string as JSON *)
      try
        let parsed = Yojson.Safe.from_string ("\"" ^ escaped ^ "\"") in
        match parsed with
        | `String s -> s = str
        | _ -> false
      with _ -> false)

(* Property: level ordering is total *)
let level_ordering_total =
  let level_gen = Gen.oneofl Level.[Verbose; Debug; Information; 
                                     Warning; Error; Fatal] in
  Test.make ~name:"level_ordering_total" ~count:1000
    (Gen.pair level_gen level_gen)
    (fun (a, b) ->
      let cmp1 = Level.compare a b in
      let cmp2 = Level.compare b a in
      (* Antisymmetry: if a < b then b > a *)
      (cmp1 < 0 && cmp2 > 0) ||
      (cmp1 > 0 && cmp2 < 0) ||
      (cmp1 = 0 && cmp2 = 0))

(* Property: level comparison matches integer comparison *)
let level_compare_matches_int =
  let level_gen = Gen.oneofl Level.[Verbose; Debug; Information;
                                     Warning; Error; Fatal] in
  Test.make ~name:"level_compare_matches_int" ~count:1000
    (Gen.pair level_gen level_gen)
    (fun (a, b) ->
      let cmp_result = Level.compare a b in
      let int_result = compare (Level.to_int a) (Level.to_int b) in
      cmp_result = int_result)

let () =
  QCheck_runner.run_tests_main
    [ parse_never_raises
    ; roundtrip_reconstruction
    ; hole_extraction_consistent
    ; escaped_braces_preserved
    ; json_escape_roundtrip
    ; level_ordering_total
    ; level_compare_matches_int
    ]
```

### Step 3: Add Failure Injection Tests

**File:** `test/test_failure_injection.ml`

```ocaml
(** Failure injection tests *)

open Alcotest
open Message_templates

(* Simulate disk full by using a temp file with quota *) 
let test_file_sink_disk_full () =
  skip_if true "requires disk quota setup";
  (* Implementation would use ulimit or filesystem tricks *)
  ()

let test_file_sink_permission_denied () =
  let read_only_dir = "/tmp" in
  let path = Filename.concat read_only_dir "test_readonly.log" in
  
  (* Try to create sink in read-only location *)
  (* This tests error handling, not permissions *)
  try
    let _sink = File_sink.create "/nonexistent/path/test.log" in
    fail "should have raised exception"
  with _ ->
    check bool "exception raised" true true

let test_async_queue_backpressure () =
  let emitted = ref [] in
  let slow_sink event = 
    Thread.delay 0.01;  (* 10ms per event *)
    emitted := event :: !emitted
  in
  
  let config = 
    { Async_sink_queue.default_config with
      max_queue_size= 10
    ; batch_size= 1
    ; flush_interval_ms= 1000 }  (* Long interval *)
  in
  
  let queue = Async_sink_queue.create config slow_sink in
  
  (* Fill queue quickly *)
  for i = 1 to 50 do
    Async_sink_queue.enqueue queue (create_test_event ())
  done;
  
  Thread.delay 0.5;
  
  let stats = Async_sink_queue.get_stats queue in
  
  (* Should have dropped events due to backpressure *)
  check bool "events were dropped" true (stats.total_dropped > 0);
  
  Async_sink_queue.close queue

let test_circuit_breaker_state_transitions () =
  let cb = Circuit_breaker.create ~failure_threshold:3 
    ~reset_timeout_ms:100 () in
  
  (* Initially Closed *)
  check circuit_breaker_state "initially closed" 
    Circuit_breaker.Closed (Circuit_breaker.get_state cb);
  
  (* 3 failures -> Open *)
  for _ = 1 to 3 do
    ignore (Circuit_breaker.call cb (fun () -> raise Exit))
  done;
  
  check circuit_breaker_state "after 3 failures" 
    Circuit_breaker.Open (Circuit_breaker.get_state cb);
  
  (* Calls should be rejected while Open *)
  check (option unit) "rejected while open"
    None (Circuit_breaker.call cb (fun () -> ()));
  
  (* Wait for timeout -> Half_open *)
  Thread.delay 0.15;
  
  check circuit_breaker_state "after timeout"
    Circuit_breaker.Half_open (Circuit_breaker.get_state cb);
  
  (* Success in Half_open -> Closed *)
  ignore (Circuit_breaker.call cb (fun () -> ()));
  
  check circuit_breaker_state "after success in half-open"
    Circuit_breaker.Closed (Circuit_breaker.get_state cb)

(* Custom checkers *)
let circuit_breaker_state =
  let pp_state ppf = function
    | Circuit_breaker.Closed -> Fmt.string ppf "Closed"
    | Circuit_breaker.Open -> Fmt.string ppf "Open"
    | Circuit_breaker.Half_open -> Fmt.string ppf "Half_open"
  in
  testable pp_state (=)

let create_test_event () =
  Log_event.create ~level:Level.Information 
    ~message_template:"Test" ~rendered_message:"Test"
    ~properties:[] ()

let () =
  run "Failure Injection Tests"
    [ ("file_sink",
        [ test_case "permission denied" `Quick test_file_sink_permission_denied
        ; test_case "disk full" `Slow test_file_sink_disk_full ] )
    ; ("async_queue",
        [ test_case "backpressure" `Quick test_async_queue_backpressure ] )
    ; ("circuit_breaker",
        [ test_case "state transitions" `Quick test_circuit_breaker_state_transitions ] )
    ]
```

### Step 4: Add Boundary Tests

**File:** `test/test_boundaries.ml`

```ocaml
(** Boundary and edge case tests *)

open Alcotest
open Message_templates

let test_file_rolling_exact_midnight () =
  (* Create file sink just before midnight UTC *)
  (* This is tricky to test without mocking time *)
  (* For now, test the rolling logic functions directly *)
  let t = ref (Ptime.of_float_s 0.0 |> Option.get) in
  
  (* Create a mock sink state *)
  let should_roll_test current_time last_roll_time =
    let epoch_current = Ptime.to_float_s current_time in
    let epoch_last = Ptime.to_float_s last_roll_time in
    let current_day = Unix.gmtime epoch_current in
    let last_day = Unix.gmtime epoch_last in
    (current_day.tm_year, current_day.tm_mon, current_day.tm_mday) <>
    (last_day.tm_year, last_day.tm_mon, last_day.tm_mday)
  in
  
  (* Test same day - no roll *)
  let t1 = Ptime.of_float_s 1000000.0 |> Option.get in
  let t2 = Ptime.of_float_s 1000001.0 |> Option.get in
  check bool "same day no roll" false (should_roll_test t2 t1);
  
  (* Test different day - should roll *)
  (* 86400 seconds = 1 day *)
  let t3 = Ptime.of_float_s (1000000.0 +. 86400.0) |> Option.get in
  check bool "different day should roll" true (should_roll_test t3 t1)

let test_empty_template () =
  match Template_parser.parse_template "" with
  | Ok parts -> check int "empty template" 0 (List.length parts)
  | Error msg -> fail ("Failed to parse empty template: " ^ msg)

let test_very_long_template () =
  let long_text = String.make 10000 'x' in
  match Template_parser.parse_template long_text with
  | Ok [Types.Text s] -> check string "long template" long_text s
  | _ -> fail "Failed to parse long template"

let test_many_holes () =
  let holes = List.init 100 (fun i -> Printf.sprintf "{var%d}" i) in
  let template = String.concat " " holes in
  match Template_parser.parse_template template with
  | Ok parts ->
      let hole_count = 
        List.length (List.filter (function Types.Hole _ -> true | _ -> false) parts)
      in
      check int "all holes parsed" 100 hole_count
  | Error msg -> fail ("Failed to parse many holes: " ^ msg)

let test_unicode_in_template () =
  let template = "User {name} from {city}" in
  let properties = 
    [("name", `String "José"); ("city", `String "東京")]
  in
  let rendered = Runtime_helpers.render_template template properties in
  check string "unicode rendered" "User José from 東京" rendered

let test_unicode_json_escaping () =
  let event = Log_event.create ~level:Level.Information
    ~message_template:"Test" ~rendered_message:"Test"
    ~properties:[("unicode", `String "Hello 世界 👋")]
    ()
  in
  let json = Log_event.to_json_string event in
  (* Should contain the unicode characters, not escaped *)
  check bool "unicode preserved" true 
    (String.contains json '世' && String.contains json '👋')

let test_timestamp_cache_millisecond_boundary () =
  (* Test that timestamps within same millisecond are cached *)
  Timestamp_cache.set_enabled true;
  
  (* Get two timestamps rapidly *)
  let t1 = Timestamp_cache.get_ptime () in
  let t2 = Timestamp_cache.get_ptime () in
  
  (* They should be identical (same cache entry) *)
  check bool "same millisecond same timestamp" true (t1 = t2);
  
  (* Wait for next millisecond *)
  Thread.delay 0.002;
  
  let t3 = Timestamp_cache.get_ptime () in
  (* Now should be different *)
  check bool "different millisecond different timestamp" true (t2 <> t3)

let test_null_characters () =
  (* JSON should handle null characters properly *)
  let event = Log_event.create ~level:Level.Information
    ~message_template:"Test\x00null" ~rendered_message:"Test\x00null"
    ~properties:[("key", `String "value\x00null")]
    ()
  in
  let json = Log_event.to_json_string event in
  (* Should not crash, should escape nulls *)
  check bool "handles null chars" true (String.length json > 0)

let test_max_int_values () =
  let properties = 
    [("max_int", `Int max_int);
     ("min_int", `Int min_int);
     ("max_int64", `Intlit (Int64.to_string Int64.max_int))]
  in
  let event = Log_event.create ~level:Level.Information
    ~message_template:"Test" ~rendered_message:"Test"
    ~properties ()
  in
  let json = Log_event.to_json_string event in
  check bool "handles max ints" true (String.length json > 0)

let () =
  run "Boundary Tests"
    [ ("file_rolling",
        [ test_case "midnight boundary" `Quick test_file_rolling_exact_midnight ] )
    ; ("parsing",
        [ test_case "empty template" `Quick test_empty_template
        ; test_case "very long template" `Quick test_very_long_template
        ; test_case "many holes" `Quick test_many_holes
        ; test_case "unicode in template" `Quick test_unicode_in_template ] )
    ; ("json",
        [ test_case "unicode escaping" `Quick test_unicode_json_escaping
        ; test_case "null characters" `Quick test_null_characters
        ; test_case "max int values" `Quick test_max_int_values ] )
    ; ("timestamp",
        [ test_case "millisecond boundary" `Quick test_timestamp_cache_millisecond_boundary ] )
    ]
```

### Step 5: Add Performance Regression Tests

**File:** `test/test_performance.ml`

```ocaml
(** Performance regression tests *)

open Alcotest
open Message_templates

let benchmark name f iterations =
  let start = Unix.gettimeofday () in
  for _ = 1 to iterations do
    f ()
  done;
  let elapsed = Unix.gettimeofday () -. start in
  let ops_per_sec = float_of_int iterations /. elapsed in
  Printf.printf "%s: %.0f ops/sec\n" name ops_per_sec;
  elapsed

let test_logger_throughput () =
  let path = Filename.temp_file "perf_test" ".log" in
  let sink = create_file_sink path in
  let logger = Logger.create ~min_level:Level.Debug ~sinks:[sink] in
  
  let iterations = 10000 in
  
  let elapsed = benchmark "logger_throughput" (fun () ->
    Logger.information logger "Test message"
      [("key1", `String "value1"); ("key2", `Int 42)]) iterations
  in
  
  Logger.close logger;
  Sys.remove path;
  
  (* Should complete 10000 logs in under 5 seconds *)
  check bool "throughput acceptable" true (elapsed < 5.0)

let test_template_parsing_speed () =
  let template = "User {username} logged in from {ip} at {timestamp}" in
  let iterations = 100000 in
  
  let elapsed = benchmark "template_parsing" (fun () ->
    match Template_parser.parse_template template with
    | Ok _ -> ()
    | Error _ -> fail "parse failed") iterations
  in
  
  (* Should parse 100k templates in under 1 second *)
  check bool "parsing speed acceptable" true (elapsed < 1.0)

let test_json_serialization_speed () =
  let event = Log_event.create ~level:Level.Information
    ~message_template:"User {username} logged in"
    ~rendered_message:"User alice logged in"
    ~properties:[("username", `String "alice");
                 ("ip", `String "192.168.1.1");
                 ("count", `Int 42)]
    ()
  in
  
  let iterations = 100000 in
  
  let elapsed = benchmark "json_serialization" (fun () ->
    ignore (Log_event.to_json_string event)) iterations
  in
  
  (* Should serialize 100k events in under 1 second *)
  check bool "serialization speed acceptable" true (elapsed < 1.0)

let test_timestamp_cache_hit_rate () =
  Timestamp_cache.set_enabled true;
  
  (* Get 1000 timestamps in rapid succession - all should hit cache *)
  let hits = ref 0 in
  let misses = ref 0 in
  
  (* Simulate cache by checking if timestamps are identical *)
  let timestamps = ref [] in
  for _ = 1 to 1000 do
    timestamps := Timestamp_cache.get_ptime () :: !timestamps
  done;
  
  (* In same millisecond, all should be equal *)
  let unique_count = 
    List.length (List.sort_uniq Ptime.compare !timestamps) 
  in
  
  (* Should have very few unique timestamps due to caching *)
  check bool "high cache hit rate" true (unique_count <= 2);
  
  Timestamp_cache.set_enabled false

let test_memory_usage () =
  (* Log many messages and check memory doesn't grow unbounded *)
  let path = Filename.temp_file "mem_test" ".log" in
  let sink = create_file_sink path in
  let logger = Logger.create ~min_level:Level.Debug ~sinks:[sink] in
  
  (* Force garbage collection to get baseline *)
  Gc.full_major ();
  let baseline = (Gc.stat ()).live_words in
  
  (* Log many messages *)
  for _ = 1 to 100000 do
    Logger.information logger "Test message" []
  done;
  
  (* Force GC again *)
  Gc.full_major ();
  let after = (Gc.stat ()).live_words in
  
  Logger.close logger;
  Sys.remove path;
  
  (* Memory should be roughly similar (within 50%) *)
  let ratio = float_of_int after /. float_of_int baseline in
  check bool "no memory leak" true (ratio < 1.5)

let () =
  run "Performance Tests"
    [ ("throughput",
        [ test_case "logger" `Slow test_logger_throughput ] )
    ; ("parsing",
        [ test_case "template parsing" `Slow test_template_parsing_speed ] )
    ; ("serialization",
        [ test_case "json" `Slow test_json_serialization_speed ] )
    ; ("caching",
        [ test_case "timestamp cache" `Quick test_timestamp_cache_hit_rate ] )
    ; ("memory",
        [ test_case "no leaks" `Slow test_memory_usage ] )
    ]
```

### Step 6: Update Dune Test Configuration

**File:** `test/dune`

```scheme
(test
 (names test_multicore test_failure_injection test_boundaries test_performance)
 (libraries message-templates alcotest))

; Update existing test configuration to include new modules
```

## Testing Strategy Summary

| Test Category | Files | Priority |
|---------------|-------|----------|
| Multicore | test_multicore.ml | High |
| Property-based | test_qcheck_*.ml (expanded) | High |
| Failure injection | test_failure_injection.ml | Medium |
| Boundaries | test_boundaries.ml | Medium |
| Performance | test_performance.ml | Low |

## Success Criteria

- [ ] Multicore tests added and passing
- [ ] Property-based tests expanded (10+ properties)
- [ ] Failure injection tests added
- [ ] Boundary tests added
- [ ] Performance benchmarks established
- [ ] CI runs all test categories
- [ ] Coverage report shows >80% code coverage

## Related Files

- `test/test_multicore.ml` (new)
- `test/test_failure_injection.ml` (new)
- `test/test_boundaries.ml` (new)
- `test/test_performance.ml` (new)
- `test/test_qcheck_*.ml` (expand)
- `test/dune`
- `.github/workflows/test.yml` (add CI config)

## Notes

- Multicore tests require OCaml 5.x
- Performance tests may be flaky on shared CI runners - consider thresholds carefully
- Property-based tests should be deterministic (set random seed)
