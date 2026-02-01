# OCaml Message Templates

A PPX-based library for Message Templates in OCaml that provides compile-time template validation with automatic variable capture from scope, plus a comprehensive logging infrastructure modeled after Serilog.

## Features

### Core Template Features
- **Compile-time Validation**: Template syntax and variable existence checked at compile time
- **Type Safety**: Hard compile errors for undefined variables
- **Dual Output**: Generate both formatted strings and structured JSON output
- **Automatic Timestamps**: All JSON output includes RFC3339 timestamps (`@t` field)
- **PPX-driven**: Full compile-time parsing and code generation for zero runtime overhead
- **Operator Support**: Special operators for structure preservation (`@`) and stringification (`$`)
- **Format Specifiers**: Support for format strings like `{count:05d}`, `{value:.2f}`, `{flag:B}`
- **High Performance**: Comparable to hand-written Printf code

### Logging Infrastructure
- **Log Levels**: Six levels (Verbose, Debug, Information, Warning, Error, Fatal) with proper ordering
- **Multiple Sinks**: Console (with colors), File (with rolling), Composite, and Null sinks
- **Structured Logging**: Automatic JSON output with timestamps and properties
- **Context Tracking**: Ambient properties that flow across function calls
- **Enrichment**: Add contextual properties automatically to all log events
- **Filtering**: Level-based and property-based filtering with logical combinators
- **Global Logger**: Static logger access similar to Serilog.Log
- **PPX Extensions**: Clean syntax with `[%log.level "message {var}"]`
- **Fluent Configuration**: Easy-to-use configuration builder API

## Installation

```bash
opam install message-templates message-templates-ppx
```

Or add to your `dune-project`:

```dune
(depends
  (ocaml (>= 5.4.0))
  message-templates
  message-templates-ppx
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
  Configuration.create ()
  |> Configuration.minimum_level Level.Information
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.write_to_file ~rolling:File_sink.Daily "app.log"
  |> Configuration.create_logger
  |> Log.set_logger
```

Log messages with variables:

```ocaml
let process_user user_id =
  Log.information "Processing user {user_id}" ["user_id", `Int user_id];

  try
    (* ... work ... *)
    Log.debug "User {user_id} processed successfully" ["user_id", `Int user_id]
  with exn ->
    Log.error ~exn "Failed to process user {user_id}" ["user_id", `Int user_id]
```

### PPX Logging (Clean Syntax)

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

  (* Static properties *)
  |> Configuration.enrich_with_property "AppVersion" (`String "1.0.0")
  |> Configuration.enrich_with_property "Environment" (`String "Production")

  (* Filters *)
  |> Configuration.filter_by_min_level Level.Information

  |> Configuration.create_logger
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

### Escaped Braces

Use doubled braces for literal braces:

```ocaml
let msg, _ = [%template "Use {{braces}} for literals"] in
(* Output: Use {braces} for literals *)
```

## Architecture

The library uses a PPX rewriter that operates at compile time:

1. **Parse**: Template string parsed into parts using Angstrom
2. **Validate**: Variable existence checked against lexical scope
3. **Generate**: OCaml code generated for both string and JSON output
4. **Zero Overhead**: No runtime parsing - all work done at compile time

### Logging Pipeline

```
Application Code
       |
       v
Level Check (fast path)
       |
       v
Template Expansion (via PPX)
       |
       v
Context Enrichment (add ambient properties)
       |
       v
Filtering (level/property-based)
       |
       v
Sinks (Console, File, etc.)
```

## JSON Output Structure

All log events include a timestamp in RFC3339 format:

```json
{
  "@t": "2026-01-31T23:54:42-00:00",
  "@mt": "User {username} logged in from {ip_address}",
  "@m": "User alice logged in from 192.168.1.1",
  "@l": "Information",
  "username": "alice",
  "ip_address": "192.168.1.1",
  "RequestId": "req-123-abc"
}
```

- `@t`: Timestamp in RFC3339 format (ISO 8601 with timezone)
- `@mt`: Message template (the original template string with placeholders)
- `@m`: Rendered message (the fully formatted message with values substituted)
- `@l`: Log level (Verbose, Debug, Information, Warning, Error, Fatal)
- Additional fields: Captured variables and context properties

The field names follow the [CLEF (Compact Log Event Format)](https://github.com/serilog/serilog-formatting-compact) convention used by Serilog and Seq.

## Performance

Benchmark results (1 million iterations each):

```
PPX Simple Template:  0.061 seconds (16,403,928 ops/sec)
Printf Simple:        0.056 seconds (17,753,142 ops/sec)
String Concat:        0.036 seconds (27,416,081 ops/sec)

PPX with Formats:     0.586 seconds (1,706,083 ops/sec)
Printf with Formats:  0.356 seconds (2,812,759 ops/sec)

PPX JSON Output:      0.232 seconds (4,313,078 ops/sec)
```

The PPX-generated code has minimal overhead compared to hand-written Printf, with the benefit of compile-time validation and automatic JSON generation with timestamps.

## Testing

Run the test suite:

```bash
dune runtest
```

This runs 59 tests:
- Level tests (6)
- Sink tests (6)
- Logger tests (7)
- Configuration tests (13)
- Global log tests (11)
- PPX comprehensive tests (8)
- PPX log level tests (8)

All tests passing ✅

## Examples

See the `examples/` directory:

### Template Examples
- `basic.ml` - Simple template usage
- `comprehensive.ml` - Advanced template features

### Logging Examples
- `logging_basic.ml` - Basic logging setup and usage
- `logging_advanced.ml` - Multiple sinks, rolling files, enrichment
- `logging_ppx.ml` - PPX extension usage

Run examples:

```bash
dune exec examples/basic.exe
dune exec examples/logging_basic.exe
dune exec examples/logging_advanced.exe
dune exec examples/logging_ppx.exe
```

## API Reference

### Core Modules

- `Level` - Log levels (Verbose, Debug, Information, Warning, Error, Fatal)
- `Log_event` - Log event type with timestamp, level, message, properties
- `Template_parser` - Template string parsing

### Sink Modules

- `Console_sink` - Console output with colors
- `File_sink` - File output with rolling (Infinite, Daily, Hourly)
- `Composite_sink` - Route to multiple sinks
- `Null_sink` - Discard all events (testing)

### Logger Modules

- `Logger` - Main logger interface with level checking and enrichment
- `Filter` - Filter predicates (level, property, all/any/not)
- `Configuration` - Fluent configuration builder
- `Log` - Global logger module
- `Log_context` - Ambient context for properties

## Compliance with Message Templates Specification

This implementation follows the Message Templates specification from https://messagetemplates.org/:

- ✅ Named property holes: `{name}`
- ✅ Positional property holes: `{0}`, `{1}`
- ✅ Escaped braces: `{{` and `}}`
- ✅ Operators: `@` for structure, `$` for stringification
- ✅ Format specifiers: `:format` syntax
- ✅ Alignment specifiers: `,width` syntax
- ✅ Timestamp field in structured output (uses CLEF `@t` convention)
- ✅ Message template field in structured output (uses CLEF `@mt` convention)
- ✅ Rendered message field in structured output (uses CLEF `@m` convention)
- ✅ Log level field in structured output (uses CLEF `@l` convention)

## License

MIT

## Acknowledgments

This implementation follows the Message Templates specification from https://messagetemplates.org/ and is inspired by Serilog's design patterns.
