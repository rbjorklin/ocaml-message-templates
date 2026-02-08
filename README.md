# OCaml Message Templates

A PPX-based library for Message Templates in OCaml that provides compile-time template validation with automatic variable capture from scope, plus a comprehensive logging infrastructure modeled after Serilog.

## Features

- Compile-time template validation with automatic variable capture from scope
- Type-safe logging with hard compile errors for undefined variables
- Dual output: formatted strings and structured JSON (CLEF format)
- PPX-driven code generation with zero runtime template parsing overhead
- Operators for structure preservation (`@`) and stringification (`$`)
- Printf-compatible format specifiers (`:05d`, `.2f`, etc.) and alignment
- Six log levels with comparison operators
- Multiple sinks: Console, File (with rolling), JSON, Composite, Null
- Async logging with non-blocking queue and circuit breaker protection
- Context tracking with ambient properties and correlation IDs
- Level-based and property-based filtering
- Per-sink metrics with latency percentiles

## Installation

### Core Library

```bash
opam install message-templates message-templates-ppx
```

### Async Support (Optional)

For Lwt (monadic concurrency):
```bash
opam install message-templates-lwt
```

For Eio (effects-based concurrency):
```bash
opam install message-templates-eio
```

### dune-project Dependencies

```dune
(depends
  (ocaml (>= 5.4.0))
  message-templates
  message-templates-ppx
  ;; Optional: choose one or both
  (message-templates-lwt (>= 0.1.0))
  (message-templates-eio (>= 0.1.0))
  yojson
  ptime
  unix)
```

## Usage

Add the PPX to your dune file:

```dune
(executable
 (name myapp)
 (libraries message-templates yojson unix)
 (preprocess (pps message-templates-ppx)))
```

### Template Basics

```ocaml
let () =
  let username = "alice" in
  let ip_address = "192.168.1.1" in

  (* Template with automatic variable capture *)
  let msg, json = [%template "User {username} logged in from {ip_address}"] in

  Printf.printf "%s\n" msg;
  (* Output: User alice logged in from 192.168.1.1 *)

  Yojson.Safe.to_string json |> print_endline;
  (* Output: {"@t":"2026-01-31T23:54:42-00:00","@mt":"User {username} logged in from {ip_address}",
              "@m":"User alice logged in from 192.168.1.1","username":"alice","ip_address":"192.168.1.1"} *)
```

### Logging Basics

Configure the global logger:

```ocaml
open Message_templates

let () =
  (* Setup logger at application startup *)
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Information
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.write_to_file ~rolling:File_sink.Daily "app.log"
    |> Configuration.build
  in
  Log.set_logger logger
```

Log messages with variables:

```ocaml
let process_user user_id =
  Log.information "Processing user {user_id}" [("user_id", `Int user_id)];

  try
    (* ... work ... *)
    Log.debug "User {user_id} processed successfully" [("user_id", `Int user_id)]
  with exn ->
    Log.error ~exn "Failed to process user {user_id}" [("user_id", `Int user_id)]
```

### Async Logging

#### Lwt Support (Monadic Concurrency)

```ocaml
open Message_templates
open Message_templates_lwt

let main () =
  (* Setup async logger *)
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Information
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.write_to_file ~rolling:Daily "app.log"
    |> Lwt_configuration.create_logger
  in

  (* All log methods return unit Lwt.t *)
  let* () = Lwt_logger.information logger "Server starting on port {port}" [("port", `Int 8080)] in

  (* Concurrent logging to multiple sinks *)
  let* () = Lwt_logger.debug logger "Debug info: {user}" [("user", `String "alice")] in

  (* Clean up *)
  Lwt_logger.close logger

let () = Lwt_main.run (main ())
```

#### Eio Support (Effects-Based Concurrency)

```ocaml
open Message_templates
open Message_templates_eio

let run ~stdout ~fs =
  Eio.Switch.run @@ fun sw ->
  (* Setup Eio logger - requires switch for fiber management *)
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Information
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.write_to_file ~rolling:Daily "app.log"
    |> Eio_configuration.create_logger ~sw
  in

  (* Synchronous logging - waits for completion *)
  Eio_logger.information logger "Server starting" [];

  (* Fire-and-forget logging - runs in background fiber *)
  Eio_logger.write_async logger "Background task started" [];

  (* Handle requests *)
  let handle_request req =
    Eio_logger.information logger "Request {method} {path}"
      [("method", `String req.method); ("path", `String req.path)]
  in

  (* Your Eio code here *)
  ()

let () = Eio_main.run @@ fun env -> run ~stdout:env#stdout ~fs:env#fs
```

### PPX Logging

Use PPX extensions for even cleaner syntax:

```ocaml
let user = "alice" in
let action = "login" in

(* All six log levels supported *)
[%log.verbose "Detailed trace: user={user}, action={action}"];
[%log.debug "Debug info: user={user}"];
[%log.information "User {user} performed {action}"];
[%log.warning "Warning for user {user}"];
[%log.error "Error for user {user}"];
[%log.fatal "Fatal error for user {user}"];
```

### Contextual Logging

Track request context across function calls:

```ocaml
let handle_request request_id user_id =
  Log_context.with_property "RequestId" (`String request_id) (fun () ->
    Log_context.with_property "UserId" (`Int user_id) (fun () ->
      Log.information "Request started" [];

      (* All logs within this scope include RequestId and UserId *)
      validate_request ();
      process_data ();

      Log.information "Request completed" []
    )
  )
```

### Correlation IDs

For distributed tracing, use correlation IDs:

```ocaml
(* Generate and use a correlation ID automatically *)
Log_context.with_correlation_id_auto (fun () ->
  Log.information "Processing request" [];
  (* All logs include correlation ID *)
  call_external_service ();
  Log.information "Request completed" []
);

(* Or use a specific correlation ID *)
Log_context.with_correlation_id "req-abc-123" (fun () ->
  (* Logs include @i field with correlation ID *)
  process_request ()
)
```

### Configuration Options

```ocaml
let logger =
  Configuration.create ()
  |> Configuration.debug  (* Set minimum level *)

  (* Console with colors *)
  |> Configuration.write_to_console
       ~colors:true
       ~stderr_threshold:Level.Warning
       ()

  (* File with daily rolling *)
  |> Configuration.write_to_file
       ~rolling:File_sink.Daily
       ~output_template:"{timestamp} [{level}] {message}"
       "logs/app.log"

  (* JSON file output for pure CLEF format *)
  |> Configuration.write_to
       (let sink = Json_sink.create "output.json" in
        { Composite_sink.emit_fn = (fun e -> Json_sink.emit sink e)
        ; flush_fn = (fun () -> Json_sink.flush sink)
        ; close_fn = (fun () -> Json_sink.close sink) })

  (* Static properties *)
  |> Configuration.enrich_with_property "AppVersion" (`String "1.0.0")
  |> Configuration.enrich_with_property "Environment" (`String "Production")

  (* Filters *)
  |> Configuration.filter_by_min_level Level.Information

  |> Configuration.build
```

### Operators

- `{var}` - Default: Standard variable substitution
- `{@var}` - Structure: Preserve as JSON structure
- `{$var}` - Stringify: Convert value to string representation

### Format Specifiers

Format specifiers work like Printf formats:

```ocaml
let count = 42 in
let score = 98.5 in
let active = true in

let msg, _ = [%template "Count: {count:05d}, Score: {score:.1f}, Active: {active:B}"] in
(* Output: Count: 00042, Score: 98.5, Active: true *)
```

Common format specifiers:
- `{var:d}` - Integer (decimal)
- `{var:05d}` - Integer with zero-padding
- `{var:f}` - Float
- `{var:.2f}` - Float with 2 decimal places
- `{var:B}` - Boolean
- `{var:s}` - String (default)

### Alignment

Control field width and alignment:

```ocaml
let name = "Alice" in
let status = "active" in

[%template "|{name,10}|{status,-10}|"]
(* Output: |     Alice|active    | *)
```

### Escaped Braces

Use doubled braces for literal braces:

```ocaml
let msg, _ = [%template "Use {{braces}} for literals"] in
(* Output: Use {braces} for literals *)
```

### Type-Safe Conversions

```ocaml
open Message_templates.Runtime_helpers.Safe_conversions

let convert = list (pair int string)
let json = convert [(1, "a"); (2, "b")]
```

Available converters: `string`, `int`, `float`, `bool`, `int64`, `int32`, `nativeint`, `char`, `unit`, `list`, `array`, `option`, `pair`, `triple`

## Architecture

The PPX rewriter operates at compile time:

1. Parse template string into parts using Angstrom
2. Validate variable existence against lexical scope
3. Generate OCaml code for string and JSON output
4. Zero runtime parsing overhead

### Logging Pipeline

**Synchronous:**
```
Application
    |
    v
Level Check
    |
    v
Template Expansion (PPX)
    |
    v
Context Enrichment
    |
    v
Filtering
    |
    v
Sinks
```

**Async:**
```
Application
    |
    v
Level Check
    |
    v
Template Expansion (PPX)
    |
    v
Enqueue
    |
    v
Background Thread
    |
    v
Circuit Breaker (optional)
    |
    v
Sinks
```

## JSON Output Structure

Log events follow the [CLEF format](https://github.com/serilog/serilog-formatting-compact):

```json
{
  "@t": "2026-01-31T23:54:42-00:00",
  "@mt": "User {username} logged in from {ip_address}",
  "@m": "User alice logged in from 192.168.1.1",
  "@l": "Information",
  "username": "alice",
  "ip_address": "192.168.1.1"
}
```

- `@t`: RFC3339 timestamp
- `@mt`: Message template
- `@m`: Rendered message
- `@l`: Log level
- `@i`: Correlation ID (optional)
- Additional fields: Template variables and context properties

## Advanced Features

### Metrics and Observability

Track per-sink performance:

```ocaml
let metrics = Metrics.create () in

(* Record event emission *)
Metrics.record_event metrics ~sink_id:"file" ~latency_us:1.5;

(* Get sink-specific metrics *)
match Metrics.get_sink_metrics metrics "file" with
| Some m ->
    Printf.printf "Events: %d, Dropped: %d, P95 latency: %.2fμs\n"
      m.events_total m.events_dropped m.latency_p95_us
| None -> ()

(* Export as JSON *)
let json = Metrics.to_json metrics
```

### Circuit Breaker

Protect against cascade failures:

```ocaml
let cb = Circuit_breaker.create ~failure_threshold:5 ~reset_timeout_ms:30000 () in

(* Protected call *)
match Circuit_breaker.call cb (fun () -> risky_operation ()) with
| Some result -> (* success *)
| None -> (* circuit open or failed *)
```

### Async Sink Queue

Non-blocking event queue for high-throughput scenarios:

```ocaml
let queue = Async_sink_queue.create
  { default_config with max_queue_size = 10000 }
  (fun event -> File_sink.emit sink event)
in

(* Non-blocking enqueue *)
Async_sink_queue.enqueue queue event;

(* Check queue depth *)
let depth = Async_sink_queue.get_queue_depth queue in

(* Graceful shutdown *)
Async_sink_queue.flush queue;
Async_sink_queue.close queue
```

### Timestamp Caching

```ocaml
Timestamp_cache.set_enabled false
```

## Performance

Benchmark results (1 million iterations):

```
PPX Simple Template:  0.061s (16M ops/sec)
Printf Simple:        0.056s (18M ops/sec)
String Concat:        0.036s (27M ops/sec)

PPX with Formats:     0.586s (1.7M ops/sec)
Printf with Formats:  0.356s (2.8M ops/sec)

PPX JSON Output:      0.232s (4.3M ops/sec)
```

PPX-generated code has minimal overhead compared to hand-written Printf.

## Testing

Run the test suite:

```bash
dune runtest
```

This runs tests across all packages:
- Core library: Level, Sink, Logger, Configuration, Global log, PPX, Parser, Circuit breaker, Metrics, Async queue tests
- Lwt package: Lwt logger and sink tests
- Eio package: Eio logger and sink tests

## Examples

See the `examples/` directory:

- `basic.ml` - Simple template usage
- `logging_basic.ml` - Basic logging setup and usage
- `logging_advanced.ml` - Multiple sinks, rolling files, enrichment
- `logging_ppx.ml` - PPX extension usage
- `logging_clef_ppx.ml` - PPX with pure JSON CLEF output
- `logging_clef_json.ml` - Structured JSON logging

Run examples:

```bash
# Core examples
dune exec examples/basic.exe
dune exec examples/logging_basic.exe
dune exec examples/logging_advanced.exe
dune exec examples/logging_ppx.exe
dune exec examples/logging_clef_ppx.exe
dune exec examples/logging_clef_json.exe

# Async examples (when available)
dune exec message-templates-lwt/examples/lwt_example.exe
dune exec message-templates-eio/examples/eio_example.exe
```

## API Reference

### Core Modules

- `Level` - Log levels with comparison operators
- `Log_event` - Log event type
- `Template_parser` - Template parsing
- `Types` - Core types

### Sinks

- `Console_sink` - Console output with colors
- `File_sink` - File output with rolling
- `Json_sink` - CLEF/JSON output
- `Composite_sink` - Multi-sink routing
- `Null_sink` - Discard events

### Logging

- `Logger` - Logger interface
- `Filter` - Event filters
- `Configuration` - Configuration builder
- `Log` - Global logger
- `Log_context` - Ambient context

### Reliability

- `Circuit_breaker` - Error recovery
- `Async_sink_queue` - Non-blocking queue
- `Metrics` - Per-sink metrics
- `Timestamp_cache` - Timestamp caching
- `Shutdown` - Graceful shutdown

### Lwt (message-templates-lwt)

- `Lwt_logger`, `Lwt_configuration`, `Lwt_file_sink`, `Lwt_console_sink`

### Eio (message-templates-eio)

- `Eio_logger`, `Eio_configuration`, `Eio_file_sink`, `Eio_console_sink`

## Compliance

Implements the [Message Templates specification](https://messagetemplates.org/):

- Named property holes: `{name}`
- Positional property holes: `{0}`, `{1}`
- Escaped braces: `{{` and `}}`
- Operators: `@` for structure, `$` for stringification
- Format specifiers: `:format` syntax
- Alignment specifiers: `,width` syntax
- CLEF output with `@t`, `@mt`, `@m`, `@l` fields

## License

MIT

## Acknowledgments

This implementation follows the Message Templates specification from https://messagetemplates.org/ and is inspired by Serilog's design patterns.
