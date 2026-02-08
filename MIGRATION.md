# Migration Guide

Migrating from other OCaml logging libraries.

## From `logs` library

| logs | Message Templates |
|------|-------------------|
| `Logs.app` | `Level.Fatal` |
| `Logs.err` | `Level.Error` |
| `Logs.warn` | `Level.Warning` |
| `Logs.info` | `Level.Information` |
| `Logs.debug` | `Level.Debug` |
| - | `Level.Verbose` |

**Before:**
```ocaml
Logs.set_reporter (Logs_fmt.reporter ());
Logs.set_level (Some Logs.Info)

Logs.info (fun m -> m "User %s logged in" username)
```

**After:**
```ocaml
let logger =
  Configuration.create ()
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.build
in
Log.set_logger logger

Log.information "User {username} logged in" [("username", `String username)]
```

**Tags to Properties:**
```ocaml
Log_context.with_property "user" (`String user) (fun () ->
  Log.information "Action performed" [])
```

## From `dolog` library

| dolog | Message Templates |
|-------|-------------------|
| `Log.fatal` | `Level.Fatal` |
| `Log.error` | `Level.Error` |
| `Log.warn` | `Level.Warning` |
| `Log.info` | `Level.Information` |
| `Log.debug` | `Level.Debug` |

**Before:**
```ocaml
Log.set_log_level Log.DEBUG;
Log.info "User %s logged in" username
```

**After:**
```ocaml
let logger =
  Configuration.create ()
  |> Configuration.debug
  |> Configuration.write_to_console ()
  |> Configuration.build
in
Log.set_logger logger

Log.information "User {username} logged in" [("username", `String username)]
```

## From Printf-style logging

**Before:**
```ocaml
Printf.printf "User %s logged in\n" username
```

**After:**
```ocaml
Log.information "User {username} logged in" [("username", `String username)]
```

### JSON Output

```ocaml
Log.information "User {username} logged in"
  [("username", `String "alice"); ("ip", `String "192.168.1.1")]

(* Console: User alice logged in *)
(* JSON: {"@t":"2026-01-31T12:00:00Z","@mt":"User {username} logged in",...} *)
```

## Common Patterns

### Basic Setup

```ocaml
let logger =
  Configuration.create ()
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.write_to_file "/var/log/app.log"
  |> Configuration.build
in
Log.set_logger logger
```

### PPX Extensions

```ocaml
let msg, json = [%template "Hello, {name}!"]
let msg, json = [%template "ID: {id:05d}"]

[%log.information "User {user} logged in"]
```

### Context Properties

```ocaml
Log_context.with_correlation_id request_id (fun () ->
  Log_context.with_property "user_id" (`String user_id) (fun () ->
    Log.information "Processing request" []))
```

### Filters

```ocaml
let logger =
  Configuration.create ()
  |> Configuration.filter_by (
       Filter.property_filter "environment" (function
         | `String "production" -> true | _ -> false))
  |> Configuration.build
```

### Multiple Sinks

```ocaml
Configuration.create ()
|> Configuration.write_to_console ~colors:true ()
|> Configuration.write_to_file "/var/log/app.log"
|> Configuration.write_to_file ~rolling:File_sink.Daily "/var/log/app-daily.log"
|> Configuration.build
```

### Exception Logging

```ocaml
try risky_operation ()
with exn ->
  Log.error ~exn "Operation failed" [("op", `String "risky")]
```

### Correlation IDs

```ocaml
Log_context.with_correlation_id_auto (fun () -> process_request ())
Log_context.with_correlation_id request_id (fun () -> handle_request ())
```

## Advanced Features

### JSON Output

```ocaml
let json_sink =
  { Composite_sink.emit_fn = (fun e -> Json_sink.emit sink_instance e)
  ; flush_fn = (fun () -> Json_sink.flush sink_instance)
  ; close_fn = (fun () -> Json_sink.close sink_instance) }
in
Configuration.create () |> Configuration.write_to json_sink |> Configuration.build
```

### Async Logging

```ocaml
let file_sink = File_sink.create "/var/log/app.log" in
let queue = Async_sink_queue.create
  { Async_sink_queue.default_config with max_queue_size = 10000 }
  (fun event -> File_sink.emit file_sink event)
in
let async_sink =
  { Composite_sink.emit_fn = Async_sink_queue.enqueue queue
  ; flush_fn = (fun () -> Async_sink_queue.flush queue)
  ; close_fn = (fun () -> Async_sink_queue.close queue) }
in
Configuration.create () |> Configuration.write_to async_sink |> Configuration.build
```

### Circuit Breaker

```ocaml
let cb = Circuit_breaker.create ~failure_threshold:5 ~reset_timeout_ms:30000 () in
match Circuit_breaker.call cb (fun () -> File_sink.emit sink event) with
| Some () -> ()
| None -> print_endline "Circuit open"
```

### Metrics

```ocaml
let metrics = Metrics.create () in
Metrics.record_event metrics ~sink_id:"file" ~latency_us:1.5;
match Metrics.get_sink_metrics metrics "file" with
| Some m when m.events_dropped > 0 -> Printf.printf "Dropped: %d\n" m.events_dropped
| _ -> ()
```

## Feature Comparison

| Feature | logs | dolog | Message Templates |
|---------|------|-------|-------------------|
| JSON output | Via reporters | No | Native CLEF |
| Log levels | 5 | 5 | 6 |
| Context/Tags | Yes | No | Yes |
| Compile-time validation | No | No | Yes (PPX) |
| Multiple sinks | Via reporters | No | Yes |
| Log rotation | No | No | Yes |
| Async logging | No | No | Yes |

## API Changes

| Old API | New API |
|---------|---------|
| `Configuration.create_logger` | `Configuration.build` |
| `Configuration.with_property` | `Configuration.enrich_with_property` |
| `Configuration.with_filter` | `Configuration.filter_by` |
| `Filter.by_level` | `Filter.level_filter` |

## Troubleshooting

### PPX Not Working

Add to dune:
```dune
(preprocess (pps message-templates-ppx))
```

### Variables Not Found

Ensure variable is in scope before template:
```ocaml
let name = "alice" in
let msg, _ = [%template "Hello, {name}!"]  (* Works *)
```

### Disable Colors

```ocaml
let colors = match Sys.getenv_opt "NO_COLOR" with Some _ -> false | None -> Unix.isatty Unix.stdout in
Configuration.create () |> Configuration.write_to_console ~colors () |> Configuration.build
```

## Migrating from Obj-Based Converters (v1.x to v2.0)

If you were using `generic_to_string` or `generic_to_json` functions, these have been deprecated in favor of the type-safe `Converter` module.

### Before (v1.x):
```ocaml
let user = { id = 42; name = "Alice" }
[%log.information "User {$user}"]
(* Used Obj module for runtime type inspection *)
```

### After (v2.0):
```ocaml
(* Define a converter for your type *)
type user = { id : int; name : string }

let user_to_json u =
  `Assoc [("id", `Int u.id); ("name", `String u.name)]

(* Use it explicitly *)
let user = { id = 42; name = "Alice" }
Log.information "User {user}" [("user", user_to_json user)]
```

### Using the Converter Module

For primitive and container types, use the `Runtime_helpers.Converter` module:

```ocaml
open Message_templates.Runtime_helpers.Converter

(* Primitives *)
let json_string = string "hello"  (* `String "hello" *)
let json_int = int 42             (* `Int 42 *)
let json_float = float 3.14       (* `Float 3.14 *)

(* Containers *)
let json_list = list int [1; 2; 3]  (* `List [`Int 1; `Int 2; `Int 3] *)
let json_opt = option string (Some "x")  (* `String "x" *)
```

### Quick Reference

| Type | Converter |
|------|-----------|
| `string` | `Converter.string` |
| `int` | `Converter.int` |
| `float` | `Converter.float` |
| `bool` | `Converter.bool` |
| `int64` | `Converter.int64` |
| `int32` | `Converter.int32` |
| `char` | `Converter.char` |
| `unit` | `Converter.unit` |
| `'a list` | `Converter.list <elem_conv>` |
| `'a array` | `Converter.array <elem_conv>` |
| `'a option` | `Converter.option <elem_conv>` |
| `'a * 'b` | `Converter.pair <a_conv> <b_conv>` |

### Convention-Based Converter Lookup

The PPX automatically looks for converters following the naming convention `<type>_to_json` or `<type>_to_yojson`:

```ocaml
type user = { id : int; name : string }

(* Define a converter following the convention *)
let user_to_json u =
  `Assoc [("id", `Int u.id); ("name", `String u.name)]

(* The PPX will automatically find and use user_to_json *)
let (u : user) = { id = 42; name = "Alice" }
let msg, json = [%template "User: {u}"]
```

This works with:
- Manual converters: `let my_type_to_json t = ...`
- ppx_deriving_yojson: generates `my_type_to_yojson` automatically
- ppx_deriving.show: generates `my_type_to_string` for stringify operator

### Custom Types

For custom types, you have three options:

**Option 1: Manual converter (simplest)**
```ocaml
type point = { x : float; y : float }

let point_to_json p =
  `Assoc [("x", `Float p.x); ("y", `Float p.y)]

(* Use with Log module *)
let p = { x = 1.0; y = 2.0 } in
Log.debug "Point" [("point", point_to_json p)]
```

**Option 2: Use ppx_deriving_yojson (recommended for many types)**

Add to your `dune` file:
```dune
(preprocess (pps ppx_deriving_yojson))
```

Then derive converters automatically:
```ocaml
type user = {
  id : int;
  name : string;
  email : string;
} [@@deriving yojson]
(* Generates: user_to_yojson and user_of_yojson *)

let user = { id = 1; name = "Alice"; email = "alice@example.com" } in
Log.information "User created" [("user", user_to_yojson user)]
```

**Option 3: Use ppx_deriving_yojson with variants and nested types**
```ocaml
type status = 
  | Active
  | Inactive of string
[@@deriving yojson]

type request = {
  id : int;
  status : status;
  user : user;
} [@@deriving yojson]

let req = { id = 1; status = Inactive "timeout"; user } in
Log.debug "Request" [("request", request_to_yojson req)]
```

### PPX with Type Annotations

When using the `[%template]` PPX extension, add explicit type annotations:

```ocaml
let (name : string) = "Alice"
let (age : int) = 30
let msg, json = [%template "{name} is {age} years old"]
```

Without type annotations, the PPX cannot determine the type for generating the converter.

## See Also

- `CONFIGURATION.md` - Configuration guide
- `DEPLOYMENT.md` - Production deployment
