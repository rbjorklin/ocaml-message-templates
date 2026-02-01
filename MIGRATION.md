# Migration Guide

This guide helps you migrate from other OCaml logging libraries to Message Templates.

## Table of Contents

- [From `logs` library](#from-logs-library)
- [From `dolog` library](#from-dolog-library)
- [From Printf-style logging](#from-printf-style-logging)
- [Common Patterns](#common-patterns)

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
    |> Configuration.create_logger
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
  ["username", `String username];
Log.debug "Processing {count} items"
  ["count", `Int count]
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
  |> Configuration.create_logger
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
  ["username", `String username];
Log.debug "Count: {count}"
  ["count", `Int count]
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
  ["username", `String username; "ip", `String ip_address];
Log.information "Count: {count:d}, Score: {score:.2f}"
  ["count", `Int count; "score", `Float score]
```

### Adding Structured Output

One major advantage of Message Templates is automatic JSON output:

```ocaml
(* This creates both a human-readable message and structured JSON *)
Log.information "User {username} logged in from {ip}"
  ["username", `String "alice"; "ip", `String "192.168.1.1"]

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
  |> Configuration.create_logger

let () =
  let logger = setup_logger () in
  Log.set_logger logger
```

### Using PPX Extensions

Message Templates provides PPX extensions for compile-time template validation:

```ocaml
(* In dune: (preprocess (pps ppx_message_templates)) *)

(* Basic template *)
let msg, json = [%template "Hello, {name}!"]

(* With format specifiers *)
let msg, json = [%template "ID: {id:05d}, Score: {score:.1f}"]

(* With operators *)
let msg, json = [%template "Data: {$data}"]  (* Stringify operator *)
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
  |> Configuration.create_logger
```

### Multiple Sinks

Send logs to multiple destinations:

```ocaml
let logger =
  Configuration.create ()
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.write_to_file "/var/log/app.log"
  |> Configuration.write_to_file ~rolling:File_sink.Daily "/var/log/app-daily.log"
  |> Configuration.create_logger
```

### Exception Logging

```ocaml
try
  risky_operation ()
with exn ->
  Log.error ~exn "Operation failed"
    ["operation", `String "risky_operation"]
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

---

## Troubleshooting

### Issue: Variables not found in template

**Solution:** Ensure variable is in scope when using PPX:
```ocaml
let name = "alice" in
let msg, _ = [%template "Hello, {name}!"]  (* Works *)

let msg, _ = [%template "Hello, {name}!"]  (* Error: name not in scope *)
let name = "alice"
```

### Issue: PPX not working

**Solution:** Add to dune file:
```dune
(library
 (name mylib)
 (preprocess (pps ppx_message_templates)))
```

### Issue: Need to disable colors in production

**Solution:** Use environment variable:
```ocaml
let colors = 
  match Sys.getenv_opt "NO_COLOR" with
  | Some _ -> false
  | None -> true

let logger =
  Configuration.create ()
  |> Configuration.write_to_console ~colors ()
  |> Configuration.create_logger
```

---

## Getting Help

- **API Documentation**: Run `dune build @doc` to generate odoc
- **Examples**: See `examples/` directory
- **Issues**: Report on GitHub
