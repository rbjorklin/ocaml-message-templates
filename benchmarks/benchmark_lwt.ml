(** Lwt async performance benchmarks for Message Templates using Core_bench

    This benchmark suite measures Lwt-specific performance characteristics:
    - Lwt logger async operations
    - Lwt sink I/O throughput
    - Lwt vs sync overhead comparison
    - Concurrent logging performance

    Run with: dune exec benchmarks/benchmark_lwt.exe -- -ascii -q 1 *)

open Core_bench
open Message_templates
open Lwt.Syntax

(* ========== Lwt Logger Benchmarks ========== *)

(** Create a null Lwt sink for benchmarking overhead *)
let create_null_lwt_sink () =
  { Message_templates_lwt.Lwt_sink.emit_fn= (fun _ -> Lwt.return ())
  ; flush_fn= (fun () -> Lwt.return ())
  ; close_fn= (fun () -> Lwt.return ()) }
;;

let lwt_logger_simple () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Information ~sinks:[(sink, None)]
  in
  Lwt_main.run (Lwt_logger.information logger "Test message" [])
;;

let lwt_logger_with_props () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Information ~sinks:[(sink, None)]
  in
  Lwt_main.run
    (Lwt_logger.information logger "User {user} scored {score}"
       [("user", `String "alice"); ("score", `Int 42)] )
;;

let lwt_logger_filtered () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Warning ~sinks:[(sink, None)]
  in
  Lwt_main.run (Lwt_logger.debug logger "Filtered message" [])
;;

let lwt_logger_multiple_sinks () =
  let open Message_templates_lwt in
  let sink1 = create_null_lwt_sink () in
  let sink2 = create_null_lwt_sink () in
  let sink3 = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Information
      ~sinks:[(sink1, None); (sink2, None); (sink3, None)]
  in
  Lwt_main.run (Lwt_logger.information logger "Multi-sink message" [])
;;

let lwt_logger_with_context () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Information ~sinks:[(sink, None)]
  in
  let contextual_logger =
    Lwt_logger.for_context logger "request_id" (`String "abc")
  in
  Lwt_main.run
    (Lwt_logger.information contextual_logger "Request processed"
       [("duration_ms", `Int 100)] )
;;

let lwt_logger_with_enricher () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
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
    Lwt_logger.create ~min_level:Level.Information ~sinks:[(sink, None)]
  in
  let enriched_logger = Lwt_logger.with_enricher logger enricher in
  Lwt_main.run (Lwt_logger.information enriched_logger "Enriched message" [])
;;

(* ========== Lwt Configuration Benchmarks ========== *)

let lwt_config_create () =
  let open Message_templates_lwt in
  let config =
    Configuration.create ()
    |> Configuration.minimum_level Level.Debug
    |> Configuration.write_to_console ~colors:true ()
  in
  ignore config
;;

let lwt_config_with_enricher () =
  let open Message_templates_lwt in
  let config =
    Configuration.create ()
    |> Configuration.minimum_level Level.Information
    |> Configuration.enrich_with (fun e -> e)
    |> Configuration.enrich_with_property "service" (`String "benchmark")
  in
  ignore config
;;

let lwt_config_with_filter () =
  let open Message_templates_lwt in
  let config =
    Configuration.create ()
    |> Configuration.filter_by_min_level Level.Warning
    |> Configuration.filter_by (Filter.matching "request_id")
  in
  ignore config
;;

let lwt_config_create_logger () =
  let open Message_templates_lwt in
  let config =
    Configuration.create () |> Configuration.write_to_console ~colors:false ()
  in
  let logger = Configuration.create_logger config in
  ignore logger
;;

(* ========== Lwt Composite Sink Benchmarks ========== *)

let lwt_composite_sink_3 () =
  let open Message_templates_lwt in
  let sink1 = create_null_lwt_sink () in
  let sink2 = create_null_lwt_sink () in
  let sink3 = create_null_lwt_sink () in
  let composite = Lwt_sink.composite_sink [sink1; sink2; sink3] in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  Lwt_main.run (composite.emit_fn event)
;;

let lwt_composite_sink_10 () =
  let open Message_templates_lwt in
  let sinks = List.init 10 (fun _ -> create_null_lwt_sink ()) in
  let composite = Lwt_sink.composite_sink sinks in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  Lwt_main.run (composite.emit_fn event)
;;

(* ========== Concurrent Logging Benchmarks ========== *)

let lwt_concurrent_10_logs () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Information ~sinks:[(sink, None)]
  in
  let logs =
    List.init 10 (fun i ->
        Lwt_logger.information logger "Concurrent log"
          [("index", `Int i); ("batch", `String "test")] )
  in
  Lwt_main.run (Lwt.join logs)
;;

let lwt_concurrent_100_logs () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Information ~sinks:[(sink, None)]
  in
  let logs =
    List.init 100 (fun i ->
        Lwt_logger.information logger "Concurrent log"
          [("index", `Int i); ("batch", `String "test")] )
  in
  Lwt_main.run (Lwt.join logs)
;;

let lwt_sequential_100_logs () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Information ~sinks:[(sink, None)]
  in
  let rec log_sequence n =
    if n <= 0 then
      Lwt.return ()
    else
      let* () =
        Lwt_logger.information logger "Sequential log" [("index", `Int n)]
      in
      log_sequence (n - 1)
  in
  Lwt_main.run (log_sequence 100)
;;

(* ========== Lwt Console Sink Benchmarks ========== *)

let lwt_console_sink_create () =
  let open Message_templates_lwt in
  let sink = Lwt_console_sink.create ~colors:false () in
  ignore sink
;;

let lwt_console_sink_emit () =
  let open Message_templates_lwt in
  let sink = Lwt_console_sink.create ~colors:false () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Console test"
      ~rendered_message:"Console test message"
      ~properties:[("key", `String "value")]
      ()
  in
  Lwt_main.run (Lwt_console_sink.emit sink event)
;;

(* ========== Lwt Sink Flush/Close Benchmarks ========== *)

let lwt_logger_flush () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Information ~sinks:[(sink, None)]
  in
  Lwt_main.run (Lwt_logger.flush logger)
;;

let lwt_logger_close () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let logger =
    Lwt_logger.create ~min_level:Level.Information ~sinks:[(sink, None)]
  in
  Lwt_main.run (Lwt_logger.close logger)
;;

(* ========== Lwt vs Sync Comparison ========== *)

let sync_null_sink_emit () =
  let sink = Null_sink.create () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  Null_sink.emit sink event
;;

let lwt_null_sink_emit () =
  let open Message_templates_lwt in
  let sink = create_null_lwt_sink () in
  let event =
    Log_event.create ~level:Level.Information ~message_template:"Test"
      ~rendered_message:"Test" ~properties:[] ()
  in
  Lwt_main.run (sink.Lwt_sink.emit_fn event)
;;

let () =
  Command_unix.run
    (Bench.make_command
       [ (* Lwt Logger Benchmarks *)
         Bench.Test.create ~name:"Lwt Logger - Simple" lwt_logger_simple
       ; Bench.Test.create ~name:"Lwt Logger - With Props" lwt_logger_with_props
       ; Bench.Test.create ~name:"Lwt Logger - Filtered" lwt_logger_filtered
       ; Bench.Test.create ~name:"Lwt Logger - 3 Sinks"
           lwt_logger_multiple_sinks
       ; Bench.Test.create ~name:"Lwt Logger - With Context"
           lwt_logger_with_context
       ; Bench.Test.create ~name:"Lwt Logger - With Enricher"
           lwt_logger_with_enricher
         (* Lwt Configuration Benchmarks *)
       ; Bench.Test.create ~name:"Lwt Config - Create" lwt_config_create
       ; Bench.Test.create ~name:"Lwt Config - With Enricher"
           lwt_config_with_enricher
       ; Bench.Test.create ~name:"Lwt Config - With Filter"
           lwt_config_with_filter
       ; Bench.Test.create ~name:"Lwt Config - Create Logger"
           lwt_config_create_logger
         (* Lwt Composite Sink Benchmarks *)
       ; Bench.Test.create ~name:"Lwt Composite Sink (3)" lwt_composite_sink_3
       ; Bench.Test.create ~name:"Lwt Composite Sink (10)" lwt_composite_sink_10
         (* Concurrent Logging Benchmarks *)
       ; Bench.Test.create ~name:"Lwt Concurrent Logs (10)"
           lwt_concurrent_10_logs
       ; Bench.Test.create ~name:"Lwt Concurrent Logs (100)"
           lwt_concurrent_100_logs
       ; Bench.Test.create ~name:"Lwt Sequential Logs (100)"
           lwt_sequential_100_logs
         (* Lwt Console Sink Benchmarks *)
       ; Bench.Test.create ~name:"Lwt Console Sink - Create"
           lwt_console_sink_create
       ; Bench.Test.create ~name:"Lwt Console Sink - Emit" lwt_console_sink_emit
         (* Lwt Lifecycle Benchmarks *)
       ; Bench.Test.create ~name:"Lwt Logger - Flush" lwt_logger_flush
       ; Bench.Test.create ~name:"Lwt Logger - Close" lwt_logger_close
         (* Lwt vs Sync Comparison *)
       ; Bench.Test.create ~name:"Sync Null Sink (baseline)" sync_null_sink_emit
       ; Bench.Test.create ~name:"Lwt Null Sink (overhead)" lwt_null_sink_emit
       ] )
;;
