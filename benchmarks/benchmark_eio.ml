(** Eio async performance benchmarks for Message Templates using Core_bench

    This benchmark suite measures Eio-specific performance characteristics:
    - Eio logger sync-style operations within fibers
    - Eio sink I/O throughput
    - Fiber-based concurrent logging performance
    - Fire-and-forget async logging

    Note: Eio benchmarks without Eio_main.run test components directly. Full
    fiber-based benchmarks require Eio_main context.

    Run with: dune exec benchmarks/benchmark_eio.exe -- -ascii -q 1 *)

open Core_bench
open Message_templates

(* ========== Eio Logger Benchmarks ========== *)

(** Create a null Eio sink for benchmarking overhead *)
let create_null_eio_sink () =
  { Message_templates_eio.Eio_sink.emit_fn= (fun _ -> ())
  ; flush_fn= (fun () -> ())
  ; close_fn= (fun () -> ()) }
;;

let eio_logger_simple () =
  let open Message_templates_eio in
  let sink = create_null_eio_sink () in
  (* Create logger without switch for simple benchmarks *)
  let logger =
    Eio_logger.create ~min_level:Level.Information ~sinks:[(sink, None)] ()
  in
  Eio_logger.information logger "Test message" []
;;

let eio_logger_with_props () =
  let open Message_templates_eio in
  let sink = create_null_eio_sink () in
  let logger =
    Eio_logger.create ~min_level:Level.Information ~sinks:[(sink, None)] ()
  in
  Eio_logger.information logger "User {user} scored {score}"
    [("user", `String "alice"); ("score", `Int 42)]
;;

let eio_logger_filtered () =
  let open Message_templates_eio in
  let sink = create_null_eio_sink () in
  let logger =
    Eio_logger.create ~min_level:Level.Warning ~sinks:[(sink, None)] ()
  in
  Eio_logger.debug logger "Filtered message" []
;;

let eio_logger_multiple_sinks () =
  let open Message_templates_eio in
  let sink1 = create_null_eio_sink () in
  let sink2 = create_null_eio_sink () in
  let sink3 = create_null_eio_sink () in
  let logger =
    Eio_logger.create ~min_level:Level.Information
      ~sinks:[(sink1, None); (sink2, None); (sink3, None)]
      ()
  in
  Eio_logger.information logger "Multi-sink message" []
;;

let eio_logger_with_context () =
  let open Message_templates_eio in
  let sink = create_null_eio_sink () in
  let logger =
    Eio_logger.create ~min_level:Level.Information ~sinks:[(sink, None)] ()
  in
  let contextual_logger =
    Eio_logger.for_context logger "request_id" (`String "abc")
  in
  Eio_logger.information contextual_logger "Request processed"
    [("duration_ms", `Int 100)]
;;

let eio_logger_with_enricher () =
  let open Message_templates_eio in
  let sink = create_null_eio_sink () in
  let enricher event =
    let props = Log_event.get_properties event in
    let new_props = ("enriched", `Bool true) :: props in
    Log_event.create
      ~timestamp:(Log_event.get_timestamp event)
      ~level:(Log_event.get_level event)
      ~message_template:(Log_event.get_message_template event)
      ~rendered_message:(Log_event.get_rendered_message event)
      ~properties:new_props
      ?exception_info:(Log_event.get_exception event)
      ()
  in
  let logger =
    Eio_logger.create ~min_level:Level.Information ~sinks:[(sink, None)] ()
  in
  let enriched_logger = Eio_logger.with_enricher logger enricher in
  Eio_logger.information enriched_logger "Enriched message" []
;;

(* ========== Eio Configuration Benchmarks ========== *)

let eio_config_create () =
  let open Message_templates_eio in
  let config =
    Configuration.create () |> Configuration.minimum_level Level.Debug
  in
  ignore config
;;

let eio_config_with_enricher () =
  let open Message_templates_eio in
  let config =
    Configuration.create ()
    |> Configuration.minimum_level Level.Information
    |> Configuration.enrich_with (fun e -> e)
    |> Configuration.enrich_with_property "service" (`String "benchmark")
  in
  ignore config
;;

let eio_config_with_filter () =
  let open Message_templates_eio in
  let config =
    Configuration.create ()
    |> Configuration.filter_by_min_level Level.Warning
    |> Configuration.filter_by (Filter.matching "request_id")
  in
  ignore config
;;

let eio_config_create_logger () =
  let open Message_templates_eio in
  let config = Configuration.create () in
  let logger = Configuration.create_logger config in
  ignore logger
;;

(* ========== Eio Composite Sink Benchmarks ========== *)

let eio_composite_sink_3 () =
  let open Message_templates_eio in
  let sink1 = create_null_eio_sink () in
  let sink2 = create_null_eio_sink () in
  let sink3 = create_null_eio_sink () in
  let composite = Eio_sink.composite_sink [sink1; sink2; sink3] in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  composite.emit_fn event
;;

let eio_composite_sink_10 () =
  let open Message_templates_eio in
  let sinks = List.init 10 (fun _ -> create_null_eio_sink ()) in
  let composite = Eio_sink.composite_sink sinks in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  composite.emit_fn event
;;

(* ========== Sequential Logging Benchmarks ========== *)

let eio_sequential_100_logs () =
  let open Message_templates_eio in
  let sink = create_null_eio_sink () in
  let logger =
    Eio_logger.create ~min_level:Level.Information ~sinks:[(sink, None)] ()
  in
  for i = 1 to 100 do
    Eio_logger.information logger "Sequential log" [("index", `Int i)]
  done
;;

(* ========== Eio Console Sink Benchmarks ========== *)

let eio_console_sink_create () =
  let open Message_templates_eio in
  let sink = Eio_console_sink.create ~colors:false () in
  ignore sink
;;

let eio_console_sink_emit () =
  let open Message_templates_eio in
  let sink = Eio_console_sink.create ~colors:false () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Console test"
      ~rendered_message:"Console test message"
      ~properties:[("key", `String "value")]
      ()
  in
  Eio_console_sink.emit sink event
;;

(* ========== Eio Sink Flush/Close Benchmarks ========== *)

let eio_logger_flush () =
  let open Message_templates_eio in
  let sink = create_null_eio_sink () in
  let logger =
    Eio_logger.create ~min_level:Level.Information ~sinks:[(sink, None)] ()
  in
  Eio_logger.flush logger
;;

let eio_logger_close () =
  let open Message_templates_eio in
  let sink = create_null_eio_sink () in
  let logger =
    Eio_logger.create ~min_level:Level.Information ~sinks:[(sink, None)] ()
  in
  Eio_logger.close logger
;;

(* ========== Eio vs Sync Comparison ========== *)

let sync_null_sink_emit () =
  let sink = Null_sink.create () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  Null_sink.emit sink event
;;

let eio_null_sink_emit () =
  let open Message_templates_eio in
  let sink = create_null_eio_sink () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  sink.Eio_sink.emit_fn event
;;

let () =
  Command_unix.run
    (Bench.make_command
       [ (* Eio Logger Benchmarks *)
         Bench.Test.create ~name:"Eio Logger - Simple" eio_logger_simple
       ; Bench.Test.create ~name:"Eio Logger - With Props" eio_logger_with_props
       ; Bench.Test.create ~name:"Eio Logger - Filtered" eio_logger_filtered
       ; Bench.Test.create ~name:"Eio Logger - 3 Sinks"
           eio_logger_multiple_sinks
       ; Bench.Test.create ~name:"Eio Logger - With Context"
           eio_logger_with_context
       ; Bench.Test.create ~name:"Eio Logger - With Enricher"
           eio_logger_with_enricher
         (* Eio Configuration Benchmarks *)
       ; Bench.Test.create ~name:"Eio Config - Create" eio_config_create
       ; Bench.Test.create ~name:"Eio Config - With Enricher"
           eio_config_with_enricher
       ; Bench.Test.create ~name:"Eio Config - With Filter"
           eio_config_with_filter
       ; Bench.Test.create ~name:"Eio Config - Create Logger"
           eio_config_create_logger
         (* Eio Composite Sink Benchmarks *)
       ; Bench.Test.create ~name:"Eio Composite Sink (3)" eio_composite_sink_3
       ; Bench.Test.create ~name:"Eio Composite Sink (10)" eio_composite_sink_10
         (* Sequential Logging *)
       ; Bench.Test.create ~name:"Eio Sequential Logs (100)"
           eio_sequential_100_logs
         (* Eio Console Sink Benchmarks *)
       ; Bench.Test.create ~name:"Eio Console Sink - Create"
           eio_console_sink_create
       ; Bench.Test.create ~name:"Eio Console Sink - Emit" eio_console_sink_emit
         (* Eio Lifecycle Benchmarks *)
       ; Bench.Test.create ~name:"Eio Logger - Flush" eio_logger_flush
       ; Bench.Test.create ~name:"Eio Logger - Close" eio_logger_close
         (* Eio vs Sync Comparison *)
       ; Bench.Test.create ~name:"Sync Null Sink (baseline)" sync_null_sink_emit
       ; Bench.Test.create ~name:"Eio Null Sink (overhead)" eio_null_sink_emit
       ] )
;;
