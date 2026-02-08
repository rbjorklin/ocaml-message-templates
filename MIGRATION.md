# Migration Guide

This guide helps you migrate from other OCaml logging libraries to Message Templates.

## Table of Contents

- [From `logs` library](#from-logs-library)
- [From `dolog` library](#from-dolog-library)
- [From Printf-style logging](#from-printf-style-logging)
- [Common Patterns](#common-patterns)
- [Advanced Features](#advanced-features)

---

## From `logs` library

### Log Level Mapping

| logs | Message Templates |
|------|-------------------|
| `Logs.app` | `Level.Fatal` |
| `Logs.err` | `Level.Error` |
| `Logs.warn` | `Level.Warning` |
| `Logs.info` | `Level.Information` |
| `Logs.debug` | `Level.Debug` |
| - | `Level.Verbose` |

### Basic Setup

**Before (logs):**
```ocaml
let setup_logs () =
  Logs.set_reporter (Logs_fmt.reporter ());
  Logs.set_level (Some Logs.Info)
```

**After (Message Templates):**
```ocaml
let setup_logging () =
  let logger =
    Configuration.create ()
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.build
  in
  Log.set_logger logger
```

### Logging Messages

**Before (logs):**
```ocaml
Logs.info (fun m -> m "User %s logged in" username);
Logs.debug (fun m -> m "Processing %d items" count)
```

**After (Message Templates):**
```ocaml
Log.information "User {username} logged in"
  [("username", `String username)];
Log.debug "Processing {count} items"
  [("count", `Int count)]
```

### Converting Tags to Properties

**Before (logs):**
```ocaml
let tag = Logs.Tag.(empty |> add user_tag user)
Logs.info ~tags:tag (fun m -> m "Action performed")
```

**After (Message Templates):**
```ocaml
Log_context.with_property "user" (`String user) (fun () ->
  Log.information "Action performed" []
)
```

---

## From `dolog` library

### Log Level Mapping

| dolog | Message Templates |
|-------|-------------------|
| `Log.fatal` | `Level.Fatal` |
| `Log.error` | `Level.Error` |
| `Log.warn` | `Level.Warning` |
| `Log.info` | `Level.Information` |
| `Log.debug` | `Level.Debug` |

### Basic Setup

**Before (dolog):**
```ocaml
Log.set_log_level Log.DEBUG;
Log.set_output stdout
```

**After (Message Templates):**
```ocaml
let logger =
  Configuration.create ()
  |> Configuration.debug
  |> Configuration.write_to_console ()
  |> Configuration.build
in
Log.set_logger logger
```

### Logging Messages

**Before (dolog):**
```ocaml
Log.info "User %s logged in" username;
Log.debug "Count: %d" count
```

**After (Message Templates):**
```ocaml
Log.information "User {username} logged in"
  [("username", `String username)];
Log.debug "Count: {count}"
  [("count", `Int count)]
```

---

## From Printf-style logging

### Converting Format Strings

**Before (Printf):**
```ocaml
Printf.printf "User %s logged in from %s\n" username ip_address;
printf "Count: %d, Score: %.2f\n" count score
```

**After (Message Templates):**
```ocaml
Log.information "User {username} logged in from {ip}"
  [("username", `String username); ("ip", `String ip_address)];
Log.information "Count: {count:d}, Score: {score:.2f}"
  [("count", `Int count); ("score", `Float score)]
```

### Adding Structured Output

One major advantage of Message Templates is automatic JSON output:

```ocaml
(* This creates both a human-readable message and structured JSON *)
Log.information "User {username} logged in from {ip}"
  [("username", `String "alice"); ("ip", `String "192.168.1.1")]

(* Console output: User alice logged in from 192.168.1.1 *)
(* JSON output: {"@t":"2026-01-31T12:00:00Z","@mt":"User {username} logged in from {ip}","@l":"Information","@m":"User alice logged in from 192.168.1.1","username":"alice","ip":"192.168.1.1"} *)
```

---

## Common Patterns

### Basic Logger Setup

```ocaml
open Message_templates

let setup_logger () =
  Configuration.create ()
  |> Configuration.minimum_level Level.Debug
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.write_to_file "/var/log/app.log"
  |> Configuration.build

let () =
  let logger = setup_logger () in
  Log.set_logger logger
```

### Using PPX Extensions

Message Templates provides PPX extensions for compile-time template validation:

```ocaml
(* In dune: (preprocess (pps message-templates-ppx)) *)

(* Basic template *)
let msg, json = [%template "Hello, {name}!"]

(* With format specifiers *)
let msg, json = [%template "ID: {id:05d}, Score: {score:.1f}"]

(* With operators *)
let msg, json = [%template "Data: {$data}"]  (* Stringify operator *)

(* Log level extensions *)
let user = "alice" in
[%log.information "User {user} logged in"]
```

### Context Properties

Carry context across function calls:

```ocaml
let process_request request_id user_id =
  Log_context.with_correlation_id request_id (fun () ->
    Log_context.with_property "user_id" (`String user_id) (fun () ->
      (* All logs within this scope include request_id and user_id *)
      Log.information "Processing request" [];
      do_work ();
      Log.information "Request completed" []
    )
  )
```

### Filters

Control which events are logged:

```ocaml
let logger =
  Configuration.create ()
  |> Configuration.minimum_level Level.Information
  |> Configuration.filter_by (
       Filter.property_filter "environment" (function
         | `String "production" -> true
         | _ -> false)
     )
  |> Configuration.build
```

### Multiple Sinks

Send logs to multiple destinations:

```ocaml
let logger =
  Configuration.create ()
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.write_to_file "/var/log/app.log"
  |> Configuration.write_to_file ~rolling:File_sink.Daily "/var/log/app-daily.log"
  |> Configuration.build
```

### Exception Logging

```ocaml
try
  risky_operation ()
with exn ->
  Log.error ~exn "Operation failed"
    [("operation", `String "risky_operation")]
```

### Correlation IDs for Distributed Tracing

```ocaml
(* Auto-generate correlation ID *)
Log_context.with_correlation_id_auto (fun () ->
  (* All logs include @i field with auto-generated ID *)
  process_request ()
)

(* Or use existing ID from HTTP header *)
Log_context.with_correlation_id request_id (fun () ->
  (* All logs include this correlation ID *)
  handle_request ()
)
```

---

## Advanced Features

### Structured JSON Output (CLEF Format)

```ocaml
(* Create pure JSON output file *)
let json_sink_instance = Json_sink.create "app.clef.json" in
let json_sink =
  { Composite_sink.emit_fn = (fun event -> Json_sink.emit json_sink_instance event)
  ; flush_fn = (fun () -> Json_sink.flush json_sink_instance)
  ; close_fn = (fun () -> Json_sink.close json_sink_instance) }
in

let logger =
  Configuration.create ()
  |> Configuration.write_to json_sink
  |> Configuration.build
```

### Async Logging for High Volume

```ocaml
(* Wrap file sink with async queue *)
let file_sink = File_sink.create "/var/log/app.log" in
let queue = Async_sink_queue.create
  { Async_sink_queue.default_config with
    max_queue_size = 10000;
    flush_interval_ms = 100 }
  (fun event -> File_sink.emit file_sink event)
in

let async_sink =
  { Composite_sink.emit_fn = Async_sink_queue.enqueue queue
  ; flush_fn = (fun () -> Async_sink_queue.flush queue)
  ; close_fn = (fun () -> Async_sink_queue.close queue) }
in

let logger =
  Configuration.create ()
  |> Configuration.write_to async_sink
  |> Configuration.build
```

### Circuit Breaker Protection

```ocaml
(* Protect against cascade failures *)
let cb = Circuit_breaker.create ~failure_threshold:5 ~reset_timeout_ms:30000 () in

let protected_emit event =
  match Circuit_breaker.call cb (fun () ->
    File_sink.emit sink event
  ) with
  | Some () -> ()
  | None -> (* Circuit open *)
      print_endline "WARNING: Logging circuit open"
```

### Metrics and Monitoring

```ocaml
(* Track per-sink metrics *)
let metrics = Metrics.create () in

(* Record event emission *)
Metrics.record_event metrics ~sink_id:"file" ~latency_us:1.5;

(* Check for issues *)
match Metrics.get_sink_metrics metrics "file" with
| Some m when m.events_dropped > 0 ->
    Printf.printf "WARNING: %d events dropped!\n" m.events_dropped
| Some m ->
    Printf.printf "P95 latency: %.2fμs\n" m.latency_p95_us
| None -> ()
```

### Type-Safe Conversions

For complex data types, use Safe_conversions:

```ocaml
open Message_templates.Runtime_helpers.Safe_conversions

(* Define converter for your type *)
type user = { id: int; name: string }

let user_to_json user =
  `Assoc [
    ("id", `Int user.id);
    ("name", `String user.name)
  ]

(* Use in logging *)
let user = { id = 1; name = "alice" } in
Log.information "User created"
  [("user", user_to_json user)]
```

---

## Feature Comparison

| Feature | logs | dolog | Message Templates |
|---------|------|-------|-------------------|
| Structured JSON output | Via reporters | No | Native CLEF |
| Log levels | 5 levels | 5 levels | 6 levels |
| Context/Tags | Yes | No | Yes (properties) |
| Compile-time validation | No | No | Yes (PPX) |
| Multiple sinks | Via reporters | No | Yes |
| Log rotation | No | No | Yes |
| Correlation IDs | Manual | No | Built-in |
| Type-safe templates | No | No | Yes |
| Async logging | No | No | Yes (with queue) |
| Circuit breaker | No | No | Yes |
| Metrics | No | No | Yes |

---

## API Changes Reference

### Configuration API

| Old API | New API |
|---------|---------|
| `Configuration.create_logger` | `Configuration.build` |
| `Configuration.with_property` | `Configuration.enrich_with_property` |
| `Configuration.with_filter` | `Configuration.filter_by` |
| `Configuration.with_enricher` | `Configuration.enrich_with` |

### Filter API

| Old API | New API |
|---------|---------|
| `Filter.by_level` | `Filter.level_filter` |
| `Filter.has_property` | `Filter.property_filter` or `Filter.matching` |
| `Filter.not` | `Filter.not_filter` |

---

## Troubleshooting

### Issue: Variables not found in template

**Solution:** Ensure variable is in scope when using PPX:
```ocaml
let name = "alice" in
let msg, _ = [%template "Hello, {name}!"]  (* Works *)

(* Error: name not in scope - declare before use *)
let msg, _ = [%template "Hello, {name}!"]
let name = "alice"
```

### Issue: PPX not working

**Solution:** Add to dune file:
```dune
(library
 (name mylib)
 (preprocess (pps message-templates-ppx)))
```

### Issue: Need to disable colors in production

**Solution:** Use environment variable:
```ocaml
let colors =
  match Sys.getenv_opt "NO_COLOR" with
  | Some _ -> false
  | None -> Unix.isatty Unix.stdout

let logger =
  Configuration.create ()
  |> Configuration.write_to_console ~colors ()
  |> Configuration.build
```

### Issue: Large objects in templates

**Solution:** Use the stringify operator or explicit conversion:
```ocaml
(* For display only - uses runtime conversion *)
let data = [1; 2; 3] in
let msg, _ = [%template "Data: {$data}"]

(* For JSON output - use explicit conversion *)
let data_json = `List (List.map (fun x -> `Int x) [1; 2; 3]) in
Log.information "Data received" [("data", data_json)]
```

---

## Getting Help

- **API Documentation**: Run `dune build @doc` to generate odoc
- **Examples**: See `examples/` directory
- **Configuration Guide**: See `CONFIGURATION.md`
- **Deployment Guide**: See `DEPLOYMENT.md`
