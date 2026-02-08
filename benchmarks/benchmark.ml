(** Comprehensive performance benchmarks for Message Templates using Core_bench

    This benchmark suite measures key performance characteristics:
    - PPX template compilation overhead
    - Log rendering performance
    - Sink I/O throughput
    - Context operation overhead
    - Filter evaluation performance

    Run with: dune exec benchmarks/benchmark.exe -- -ascii -q 1 *)

open Core_bench
open Message_templates

(* ========== PPX Template Benchmarks ========== *)
let ppx_simple () =
  let username = "alice" in
  let ip = "192.168.1.1" in
  let msg, _ = [%template "User {username} logged in from {ip}"] in
  msg
;;

let ppx_single_var () =
  let name = "test" in
  let msg, _ = [%template "Hello {name}"] in
  msg
;;

let ppx_many_vars () =
  let a = "1" in
  let b = "2" in
  let c = "3" in
  let d = "4" in
  let e = "5" in
  let msg, _ = [%template "{a}-{b}-{c}-{d}-{e}"] in
  msg
;;

let ppx_formats () =
  let count = 42 in
  let score = 98.5 in
  let active = true in
  let msg, _ =
    [%template "Count: {count:d}, Score: {score:f}, Active: {active:B}"]
  in
  msg
;;

let ppx_json () =
  let user = "bob" in
  let action = "login" in
  let _, json = [%template "User {user} performed {action}"] in
  Yojson.Safe.to_string json
;;

(* ========== Printf Baseline Benchmarks ========== *)
let printf_simple () =
  let username = "alice" in
  let ip = "192.168.1.1" in
  Printf.sprintf "User %s logged in from %s" username ip
;;

let string_concat () =
  let username = "alice" in
  let ip = "192.168.1.1" in
  "User " ^ username ^ " logged in from " ^ ip
;;

let printf_formats () =
  let count = 42 in
  let score = 98.5 in
  let active = true in
  Printf.sprintf "Count: %d, Score: %f, Active: %B" count score active
;;

(* ========== Sink Performance Benchmarks ========== *)
let null_sink_emit () =
  let sink = Null_sink.create () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test message"
      ~rendered_message:"Test message" ~properties:[] ()
  in
  Null_sink.emit sink event
;;

let console_sink_emit () =
  let sink = Console_sink.create () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test {msg}"
      ~rendered_message:"Test message"
      ~properties:[("msg", `String "event")]
      ()
  in
  Console_sink.emit sink event
;;

let composite_sink_emit () =
  let sink1 =
    { Composite_sink.emit_fn= (fun _ -> ())
    ; flush_fn= (fun () -> ())
    ; close_fn= (fun () -> ())
    ; min_level= None }
  in
  let sink2 =
    { Composite_sink.emit_fn= (fun _ -> ())
    ; flush_fn= (fun () -> ())
    ; close_fn= (fun () -> ())
    ; min_level= None }
  in
  let sink3 =
    { Composite_sink.emit_fn= (fun _ -> ())
    ; flush_fn= (fun () -> ())
    ; close_fn= (fun () -> ())
    ; min_level= None }
  in
  let composite = Composite_sink.create [sink1; sink2; sink3] in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  Composite_sink.emit composite event
;;

(* ========== Context Operations Benchmarks ========== *)
let context_push_pop () =
  Log_context.with_property "key" (`String "value") (fun () -> ())
;;

let context_nested () =
  Log_context.with_property "k1" (`String "v1") (fun () ->
      Log_context.with_property "k2" (`String "v2") (fun () ->
          Log_context.with_property "k3" (`String "v3") (fun () -> ()) ) )
;;

(* ========== Filter Performance Benchmarks ========== *)
let level_filter_eval () =
  let filter = Filter.level_filter Level.Information in
  let event =
    Log_event.create ~level:Level.Debug ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  filter event
;;

let property_filter_eval () =
  let filter = Filter.matching "user_id" in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test"
      ~properties:[("user_id", `String "123")]
      ()
  in
  filter event
;;

let combined_filters_eval () =
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
  filter event
;;

(* ========== Event Creation Benchmarks ========== *)
let create_simple_event () =
  Log_event.create ~level:Level.Information ~message_template:"Test"
    ~rendered_message:"Test" ~properties:[] ()
;;

let create_event_with_props () =
  let props =
    [ ("user", `String "alice")
    ; ("count", `Int 42)
    ; ("score", `Float 98.5)
    ; ("active", `Bool true) ]
  in
  Log_event.create ~level:Level.Information
    ~message_template:"User {user} scored {count}"
    ~rendered_message:"User alice scored 42" ~properties:props ()
;;

let event_to_json_string () =
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test {name}"
      ~rendered_message:"Test event"
      ~properties:[("name", `String "event"); ("count", `Int 42)]
      ()
  in
  Log_event.to_json_string event
;;

(* ========== Level Operations Benchmarks ========== *)
let level_compare () = Level.compare Level.Debug Level.Information

let level_of_string () = Level.of_string "Information"

let level_to_string () = Level.to_string Level.Warning

(* ========== Timestamp Cache Benchmarks ========== *)

let timestamp_cache_hit () =
  (* Rapid calls in same millisecond - should hit cache *)
  for _ = 1 to 1000 do
    ignore (Timestamp_cache.get_rfc3339 ())
  done
;;

let timestamp_cache_disabled () =
  Timestamp_cache.set_enabled false;
  for _ = 1 to 1000 do
    ignore (Timestamp_cache.get_rfc3339 ())
  done;
  Timestamp_cache.set_enabled true
;;

let event_creation_cached () =
  (* Event creation uses cached timestamp *)
  for _ = 1 to 1000 do
    ignore
      (Log_event.create ~level:Level.Information
         ~message_template:"Test message" ~rendered_message:"Test message"
         ~properties:[] () )
  done
;;

let ppx_timestamp () =
  (* PPX generates timestamp expression *)
  let _, json = [%template "Test message"] in
  ignore json
;;

let () =
  Command_unix.run
    (Bench.make_command
       [ Bench.Test.create ~name:"PPX Simple (2 vars)" ppx_simple
       ; Bench.Test.create ~name:"PPX Single Var" ppx_single_var
       ; Bench.Test.create ~name:"PPX Many Vars (5)" ppx_many_vars
       ; Bench.Test.create ~name:"PPX with Formats" ppx_formats
       ; Bench.Test.create ~name:"PPX JSON Output" ppx_json
       ; Bench.Test.create ~name:"Printf Simple" printf_simple
       ; Bench.Test.create ~name:"String Concat" string_concat
       ; Bench.Test.create ~name:"Printf with Formats" printf_formats
       ; Bench.Test.create ~name:"Null Sink" null_sink_emit
       ; Bench.Test.create ~name:"Console Sink" console_sink_emit
       ; Bench.Test.create ~name:"Composite Sink (3)" composite_sink_emit
       ; Bench.Test.create ~name:"Context push/pop" context_push_pop
       ; Bench.Test.create ~name:"Context nested (3)" context_nested
       ; Bench.Test.create ~name:"Level filter" level_filter_eval
       ; Bench.Test.create ~name:"Property filter" property_filter_eval
       ; Bench.Test.create ~name:"Combined filters" combined_filters_eval
       ; Bench.Test.create ~name:"Create simple event" create_simple_event
       ; Bench.Test.create ~name:"Create event + props" create_event_with_props
       ; Bench.Test.create ~name:"Event to JSON string" event_to_json_string
       ; Bench.Test.create ~name:"Level.compare" level_compare
       ; Bench.Test.create ~name:"Level.of_string" level_of_string
       ; Bench.Test.create ~name:"Level.to_string" level_to_string
       ; Bench.Test.create ~name:"Timestamp cache hit" timestamp_cache_hit
       ; Bench.Test.create ~name:"Timestamp cache disabled"
           timestamp_cache_disabled
       ; Bench.Test.create ~name:"Event creation cached" event_creation_cached
       ; Bench.Test.create ~name:"PPX timestamp" ppx_timestamp ] )
;;
