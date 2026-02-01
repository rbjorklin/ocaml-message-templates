(** Comprehensive performance benchmarks for Message Templates *)

open Message_templates

let iterations = 1_000_000

let medium_iterations = 100_000

let timeit ?(iterations = iterations) name f =
  let start = Unix.gettimeofday () in
  for _ = 1 to iterations do
    ignore (f ())
  done;
  let elapsed = Unix.gettimeofday () -. start in
  let ops_per_sec = float_of_int iterations /. elapsed in
  Printf.printf "  %-40s %8.3f sec  %10.0f ops/sec\n" name elapsed ops_per_sec
;;

(* ========== PPX Template Benchmarks ========== *)

let benchmark_ppx_simple () =
  let username = "alice" in
  let ip = "192.168.1.1" in
  fun () ->
    let msg, _ = [%template "User {username} logged in from {ip}"] in
    msg
;;

let benchmark_printf_simple () =
  let username = "alice" in
  let ip = "192.168.1.1" in
  fun () -> Printf.sprintf "User %s logged in from %s" username ip
;;

let benchmark_string_concat () =
  let username = "alice" in
  let ip = "192.168.1.1" in
  fun () -> "User " ^ username ^ " logged in from " ^ ip
;;

let benchmark_ppx_formats () =
  let count = 42 in
  let score = 98.5 in
  let active = true in
  fun () ->
    let msg, _ =
      [%template "Count: {count:d}, Score: {score:f}, Active: {active:B}"]
    in
    msg
;;

let benchmark_printf_formats () =
  let count = 42 in
  let score = 98.5 in
  let active = true in
  fun () -> Printf.sprintf "Count: %d, Score: %f, Active: %B" count score active
;;

let benchmark_ppx_json () =
  let user = "bob" in
  let action = "login" in
  fun () ->
    let _, json = [%template "User {user} performed {action}"] in
    Yojson.Safe.to_string json
;;

let benchmark_ppx_single_var () =
  let name = "test" in
  fun () ->
    let msg, _ = [%template "Hello {name}"] in
    msg
;;

let benchmark_concat_single () =
  let name = "test" in
  fun () -> "Hello " ^ name
;;

let benchmark_ppx_many_vars () =
  let a = "1" in
  let b = "2" in
  let c = "3" in
  let d = "4" in
  let e = "5" in
  fun () ->
    let msg, _ = [%template "{a}-{b}-{c}-{d}-{e}"] in
    msg
;;

(* ========== Sink I/O Benchmarks ========== *)

let benchmark_null_sink () =
  let sink = Null_sink.create () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test message"
      ~rendered_message:"Test message" ~properties:[] ()
  in
  fun () -> Null_sink.emit sink event
;;

let benchmark_file_sink () =
  let temp_file = Filename.temp_file "bench_sink_" ".log" in
  let sink = File_sink.create temp_file in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test message"
      ~rendered_message:"Test message"
      ~properties:[("key", `String "value")]
      ()
  in
  fun () -> File_sink.emit sink event
;;

let benchmark_json_sink () =
  let temp_file = Filename.temp_file "bench_json_" ".json" in
  let sink = Json_sink.create temp_file in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test {name}"
      ~rendered_message:"Test event"
      ~properties:[("name", `String "event")]
      ()
  in
  fun () -> Json_sink.emit sink event
;;

let benchmark_composite_sink () =
  let sink1 =
    { Composite_sink.emit_fn= (fun _ -> ())
    ; flush_fn= (fun () -> ())
    ; close_fn= (fun () -> ()) }
  in
  let sink2 =
    { Composite_sink.emit_fn= (fun _ -> ())
    ; flush_fn= (fun () -> ())
    ; close_fn= (fun () -> ()) }
  in
  let sink3 =
    { Composite_sink.emit_fn= (fun _ -> ())
    ; flush_fn= (fun () -> ())
    ; close_fn= (fun () -> ()) }
  in
  let composite = Composite_sink.create [sink1; sink2; sink3] in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  fun () -> Composite_sink.emit composite event
;;

(* ========== Context Operations Benchmarks ========== *)

let benchmark_context_push_pop () =
 fun () -> Log_context.with_property "key" (`String "value") (fun () -> ())
;;

let benchmark_context_nested () =
 fun () ->
  Log_context.with_property "k1" (`String "v1") (fun () ->
      Log_context.with_property "k2" (`String "v2") (fun () ->
          Log_context.with_property "k3" (`String "v3") (fun () -> ()) ) )
;;

let benchmark_context_with_scope () =
 fun () ->
  Log_context.with_scope (fun () ->
      Log_context.push_property "a" (`String "1");
      Log_context.push_property "b" (`String "2");
      Log_context.push_property "c" (`String "3");
      () )
;;

(* ========== Filter Performance Benchmarks ========== *)

let benchmark_level_filter () =
  let filter = Filter.level_filter Level.Information in
  let event =
    Log_event.create ~level:Level.Debug ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  fun () -> filter event
;;

let benchmark_property_filter () =
  let filter = Filter.matching "user_id" in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test"
      ~properties:[("user_id", `String "123")]
      ()
  in
  fun () -> filter event
;;

let benchmark_all_filter () =
  let filter =
    Filter.all
      [Filter.level_filter Level.Information; Filter.matching "request_id"]
  in
  let event =
    Log_event.create ~level:Level.Warning ~message_template:"Test"
      ~rendered_message:"Test"
      ~properties:[("request_id", `String "abc")]
      ()
  in
  fun () -> filter event
;;

(* ========== Log Event Creation Benchmarks ========== *)

let benchmark_create_event_simple () =
 fun () ->
  Log_event.create ~level:Level.Information ~message_template:"Simple message"
    ~rendered_message:"Simple message" ~properties:[] ()
;;

let benchmark_create_event_with_props () =
  let props =
    [ ("user", `String "alice")
    ; ("count", `Int 42)
    ; ("score", `Float 98.5)
    ; ("active", `Bool true) ]
  in
  fun () ->
    Log_event.create ~level:Level.Information
      ~message_template:"User {user} scored {count}"
      ~rendered_message:"User alice scored 42" ~properties:props ()
;;

let benchmark_to_json_string () =
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test {name}"
      ~rendered_message:"Test event"
      ~properties:[("name", `String "event"); ("count", `Int 42)]
      ()
  in
  fun () -> Log_event.to_json_string event
;;

let benchmark_to_yojson () =
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test {name}"
      ~rendered_message:"Test event"
      ~properties:[("name", `String "event"); ("count", `Int 42)]
      ()
  in
  fun () -> Log_event.to_yojson event
;;

(* ========== Level Operations Benchmarks ========== *)

let benchmark_level_compare () =
 fun () -> Level.compare Level.Debug Level.Information
;;

let benchmark_level_of_string () = fun () -> Level.of_string "Information"

let benchmark_level_to_string () = fun () -> Level.to_string Level.Warning

(* ========== Main ========== *)

let () =
  Printf.printf "\n";
  Printf.printf
    "╔═══════════════════════════════════════════════════════════════╗\n";
  Printf.printf
    "║   Message Templates - Comprehensive Performance Benchmarks   ║\n";
  Printf.printf
    "╚═══════════════════════════════════════════════════════════════╝\n";
  Printf.printf "\n";

  (* Template Rendering Benchmarks *)
  Printf.printf "Template Rendering (1M iterations each)\n";
  Printf.printf
    "────────────────────────────────────────────────────────────────\n";
  timeit "PPX Simple (2 vars)" (benchmark_ppx_simple ());
  timeit "Printf Simple" (benchmark_printf_simple ());
  timeit "String Concat" (benchmark_string_concat ());
  timeit "PPX Single Var" (benchmark_ppx_single_var ());
  timeit "Concat Single" (benchmark_concat_single ());
  timeit "PPX Many Vars (5)" (benchmark_ppx_many_vars ());
  Printf.printf "\n";

  (* Format Specifier Benchmarks *)
  Printf.printf "Format Specifiers (1M iterations each)\n";
  Printf.printf
    "────────────────────────────────────────────────────────────────\n";
  timeit "PPX with Formats" (benchmark_ppx_formats ());
  timeit "Printf with Formats" (benchmark_printf_formats ());
  Printf.printf "\n";

  (* JSON Generation Benchmarks *)
  Printf.printf "JSON Generation (1M iterations each)\n";
  Printf.printf
    "────────────────────────────────────────────────────────────────\n";
  timeit "PPX JSON Output" (benchmark_ppx_json ());
  timeit "LogEvent.to_json_string" (benchmark_to_json_string ());
  timeit "LogEvent.to_yojson" (benchmark_to_yojson ());
  Printf.printf "\n";

  (* Sink I/O Benchmarks *)
  Printf.printf "Sink I/O (100K iterations each)\n";
  Printf.printf
    "────────────────────────────────────────────────────────────────\n";
  timeit ~iterations:medium_iterations "Null Sink" (benchmark_null_sink ());
  timeit ~iterations:medium_iterations "File Sink" (benchmark_file_sink ());
  timeit ~iterations:medium_iterations "JSON Sink" (benchmark_json_sink ());
  timeit ~iterations:medium_iterations "Composite Sink (3)"
    (benchmark_composite_sink ());
  Printf.printf "\n";

  (* Context Operations Benchmarks *)
  Printf.printf "Context Operations (1M iterations each)\n";
  Printf.printf
    "────────────────────────────────────────────────────────────────\n";
  timeit "Context push/pop" (benchmark_context_push_pop ());
  timeit "Context nested (3)" (benchmark_context_nested ());
  timeit "Context with_scope" (benchmark_context_with_scope ());
  Printf.printf "\n";

  (* Filter Performance Benchmarks *)
  Printf.printf "Filter Performance (1M iterations each)\n";
  Printf.printf
    "────────────────────────────────────────────────────────────────\n";
  timeit "Level filter" (benchmark_level_filter ());
  timeit "Property filter" (benchmark_property_filter ());
  timeit "All filter (2 preds)" (benchmark_all_filter ());
  Printf.printf "\n";

  (* Event Creation Benchmarks *)
  Printf.printf "Event Creation (1M iterations each)\n";
  Printf.printf
    "────────────────────────────────────────────────────────────────\n";
  timeit "Create event simple" (benchmark_create_event_simple ());
  timeit "Create event + props" (benchmark_create_event_with_props ());
  Printf.printf "\n";

  (* Level Operations *)
  Printf.printf "Level Operations (1M iterations each)\n";
  Printf.printf
    "────────────────────────────────────────────────────────────────\n";
  timeit "Level.compare" (benchmark_level_compare ());
  timeit "Level.of_string" (benchmark_level_of_string ());
  timeit "Level.to_string" (benchmark_level_to_string ());
  Printf.printf "\n";

  Printf.printf "Benchmark complete!\n\n"
;;
