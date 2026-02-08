# Message Templates Configuration Guide

Complete guide to configuring loggers in Message Templates.

## Quick Start

### Minimal Setup (Console Only)

```ocaml
open Message_templates

let () =
  Configuration.create ()
  |> Configuration.write_to_console ()
  |> Configuration.build
  |> Log.set_logger;
  Log.information "Application started" []
```

### Production Setup (File + Console)

```ocaml
let () =
  let logger =
    Configuration.create ()
    |> Configuration.information  (* Set minimum level *)
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.write_to_file ~rolling:File_sink.Daily "app.log"
    |> Configuration.build
  in
  Log.set_logger logger;
  Log.information "Application started" []
```

### High-Volume Logging

```ocaml
let () =
  let logger =
    Configuration.create ()
    |> Configuration.warning  (* Only warnings and above *)
    |> Configuration.write_to_file ~rolling:File_sink.Hourly "app.log"
    |> Configuration.write_to_file ~rolling:File_sink.Infinite "errors.log"
        ~min_level:Level.Error
    |> Configuration.build
  in
  Log.set_logger logger
```

---

## Fluent API Overview

The configuration API uses a **fluent builder pattern** where each method returns a modified configuration:

```ocaml
Configuration.create ()
  |> method1
  |> method2
  |> method3
  |> Configuration.build
```

This makes it easy to:
- Chain operations
- Conditionally add configurations
- Compose reusable configuration pieces

### Example: Conditional Configuration

```ocaml
let make_logger ~debug_mode =
  let config =
    Configuration.create ()
    |> Configuration.write_to_console ()
  in
  let config =
    if debug_mode then
      config |> Configuration.debug  (* More verbose *)
    else
      config |> Configuration.information
  in
  config
  |> Configuration.write_to_file "app.log"
  |> Configuration.build
```

---

## Configuration Methods

### Log Levels

#### Set Minimum Level

The **minimum level** controls what events are logged (fast-path filtering):

```ocaml
(* Individual level methods *)
Configuration.verbose config      (* 0 - Most detailed *)
Configuration.debug config        (* 1 - Internal events *)
Configuration.information config  (* 2 - Normal operational *)
Configuration.warning config      (* 3 - Suspicious conditions *)
Configuration.error config        (* 4 - Functionality lost *)
Configuration.fatal config        (* 5 - System failure *)

(* Or use the generic method *)
Configuration.minimum_level Level.Information config
```

**Best Practice**: Set the minimum level first (it's fast)

```ocaml
Configuration.create ()
|> Configuration.information  (* Fast-path optimization *)
|> Configuration.write_to_console ()
```

#### Why This Matters

Events below the minimum level are discarded instantly without processing:

```ocaml
(* This is very fast - debug is filtered at the level check *)
Log.debug "Detailed trace: {var1} {var2} {var3}"
  [("var1", `String v1); ("var2", `String v2); ("var3", `String v3)]
```

---

### Sinks (Output Destinations)

#### Console Sink

Output logs to standard output with optional colors:

```ocaml
(* Basic console output *)
Configuration.write_to_console ()

(* With colors and stderr for high-level messages *)
Configuration.write_to_console
  ~colors:true
  ~stderr_threshold:Level.Warning
  ()

(* Custom output template *)
Configuration.write_to_console
  ~output_template:"{timestamp} [{level}] {message}"
  ()

(* Disable colors on non-TTY *)
Configuration.write_to_console
  ~colors:(Unix.isatty Unix.stdout)
  ()
```

**Parameters:**
- `colors` (bool): Enable ANSI color codes
- `stderr_threshold` (Level.t): Errors and above go to stderr, others to stdout
- `output_template` (string): Format template for console output

#### File Sink

Output logs to a file with optional rotation:

```ocaml
(* Simple file output *)
Configuration.write_to_file "app.log"

(* With daily rotation *)
Configuration.write_to_file
  ~rolling:File_sink.Daily
  "logs/app.log"

(* With hourly rotation for high-volume apps *)
Configuration.write_to_file
  ~rolling:File_sink.Hourly
  "logs/app.log"

(* Never roll - single file *)
Configuration.write_to_file
  ~rolling:File_sink.Infinite
  "logs/app.log"

(* With custom output template *)
Configuration.write_to_file
  ~output_template:"{timestamp} [{level}] {message}"
  "logs/app.log"
```

**Rolling Strategies:**
- `Infinite`: Single file, no rotation
- `Daily`: New file each day (appends `-YYYYMMDD` to filename)
- `Hourly`: New file each hour (appends `-YYYYMMDDHH` to filename)

**Best Practice**: Use `Daily` for most applications

#### JSON Sink

Output pure CLEF/JSON structured logging:

```ocaml
(* Create JSON file sink *)
let json_sink_instance = Json_sink.create "output.clef.json" in
let json_sink =
  { Composite_sink.emit_fn = (fun event -> Json_sink.emit json_sink_instance event)
  ; flush_fn = (fun () -> Json_sink.flush json_sink_instance)
  ; close_fn = (fun () -> Json_sink.close json_sink_instance) }
in

Configuration.create ()
|> Configuration.write_to json_sink
|> Configuration.build
```

#### Null Sink

Discard all logs (useful for testing):

```ocaml
Configuration.write_to_null ()
```

#### Custom Sinks

Add custom sinks using `write_to`:

```ocaml
let my_custom_sink =
  { Composite_sink.emit_fn = (fun event ->
      (* Your custom emit logic *)
      print_endline (Log_event.message event))
  ; flush_fn = (fun () -> ())
  ; close_fn = (fun () -> ()) }
in

Configuration.create ()
|> Configuration.write_to my_custom_sink
|> Configuration.build
```

#### Multiple Sinks

Add multiple sinks to output to multiple destinations:

```ocaml
Configuration.create ()
|> Configuration.write_to_console ~colors:true ()
|> Configuration.write_to_file "app.log"
|> Configuration.write_to_file "errors.log" ~min_level:Level.Error
|> Configuration.build
```

Events go to **all sinks** that pass their filters.

---

### Per-Sink Configuration

Each sink can have its own minimum level:

```ocaml
(* Console gets debug and above *)
|> Configuration.write_to_console ~min_level:Level.Debug ()

(* File only gets errors *)
|> Configuration.write_to_file "errors.log" ~min_level:Level.Error

(* Default file gets information and above *)
|> Configuration.write_to_file "app.log"
```

**When to use:**
- Console: Lower threshold for development
- File: Higher threshold for production
- Errors file: Only critical issues

---

### Filtering

#### Filter by Minimum Level (Built-in)

The `minimum_level` does level-based filtering automatically. For additional filtering:

```ocaml
Configuration.filter_by_min_level Level.Warning config
```

#### Filter by Property

Only log events with specific properties:

```ocaml
Configuration.filter_by
  (Filter.property_filter "component" (function
    | `String "auth" -> true
    | _ -> false))
  config
```

#### Combine Filters with AND/OR/NOT

```ocaml
(* All of these must match *)
Configuration.filter_by
  (Filter.all [
    Filter.level_filter Level.Warning;
    Filter.property_filter "service" (fun _ -> true)
  ])
  config

(* At least one must match *)
Configuration.filter_by
  (Filter.any [
    Filter.level_filter Level.Error;
    Filter.matching "retry_count"
  ])
  config

(* Invert a filter *)
Configuration.filter_by
  (Filter.not_filter Filter.always_block)
  config
```

---

### Enrichment

Add properties automatically to all log events:

```ocaml
Configuration.create ()
|> Configuration.enrich_with_property "version" (`String "1.2.3")
|> Configuration.enrich_with_property "environment" (`String "production")
|> Configuration.enrich_with (fun event ->
    (* Add computed properties to event *)
    event)
|> Configuration.build
```

**When to use:**
- Version information
- Environment (prod/staging/dev)
- Service name
- Instance ID
- Region

---

## Common Configuration Patterns

### Development Configuration

```ocaml
let dev_logger () =
  Configuration.create ()
  |> Configuration.debug          (* Verbose *)
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.enrich_with_property "env" (`String "dev")
  |> Configuration.build
```

### Production Configuration

```ocaml
let prod_logger () =
  Configuration.create ()
  |> Configuration.information    (* Normal level *)
  |> Configuration.write_to_console ()
  |> Configuration.write_to_file
       ~rolling:File_sink.Daily
       "/var/log/app/app.log"
  |> Configuration.write_to_file
       ~rolling:File_sink.Daily
       ~min_level:Level.Error
       "/var/log/app/errors.log"
  |> Configuration.enrich_with_property "env" (`String "prod")
  |> Configuration.enrich_with_property "hostname" (`String (Unix.gethostname ()))
  |> Configuration.build
```

### Testing Configuration

```ocaml
let test_logger () =
  Configuration.create ()
  |> Configuration.write_to_null ()  (* Discard all logs *)
  |> Configuration.build
```

### Staging Configuration

```ocaml
let staging_logger () =
  Configuration.create ()
  |> Configuration.warning          (* Less verbose than dev *)
  |> Configuration.write_to_console ()
  |> Configuration.write_to_file "/var/log/app/staging.log"
  |> Configuration.enrich_with_property "env" (`String "staging")
  |> Configuration.build
```

---

## Advanced Patterns

### Configuration from Environment

```ocaml
let logger_from_env () =
  let env = Sys.getenv_opt "APP_ENV" |> Option.value ~default:"dev" in
  let level =
    match Sys.getenv_opt "LOG_LEVEL" with
    | Some "verbose" -> Level.Verbose
    | Some "debug" -> Level.Debug
    | Some "warning" -> Level.Warning
    | Some "error" -> Level.Error
    | _ -> Level.Information
  in

  Configuration.create ()
  |> Configuration.minimum_level level
  |> Configuration.write_to_console ~colors:true ()
  |> (match Sys.getenv_opt "LOG_FILE" with
      | Some path -> Configuration.write_to_file path
      | None -> fun c -> c)
  |> Configuration.enrich_with_property "env" (`String env)
  |> Configuration.build
```

### Per-Module Loggers

```ocaml
(* Each module has its own configuration *)
module Auth = struct
  let logger =
    Configuration.create ()
    |> Configuration.information
    |> Configuration.write_to_file "auth.log"
    |> Configuration.enrich_with_property "module" (`String "auth")
    |> Configuration.build
end

module Api = struct
  let logger =
    Configuration.create ()
    |> Configuration.debug  (* More verbose for API *)
    |> Configuration.write_to_file "api.log"
    |> Configuration.enrich_with_property "module" (`String "api")
    |> Configuration.build
end
```

### Conditional Enrichment

```ocaml
let make_logger ~user_id ~request_id =
  let config = Configuration.create () in
  let config = match user_id with
    | Some uid -> Configuration.enrich_with_property "user_id" (`String uid) config
    | None -> config
  in
  let config = match request_id with
    | Some req -> Configuration.enrich_with_property "request_id" (`String req) config
    | None -> config
  in
  config
  |> Configuration.write_to_file "app.log"
  |> Configuration.build
```

---

## Output Templates

Control the format of log output with templates:

### Template Variables

- `{timestamp}` - Timestamp (RFC3339 format via `Runtime_helpers.format_timestamp`)
- `{level}` - Log level name (or use `{level:short}` for 3-char code)
- `{message}` - Rendered message (with values substituted)
- Custom properties are accessed via enrichers, not directly in templates

### Default Templates

**Console:**
```
[{timestamp} {level}] {message}
```

**File:**
```
{timestamp} [{level}] {message}
```

### Custom Examples

```ocaml
(* Compact console output *)
Configuration.write_to_console
  ~output_template:"[{level:short}] {message}"
  ()

(* Verbose file output with date only *)
Configuration.write_to_file
  ~output_template:"{timestamp} [{level}] {message}"
  "app.log"
```

### Log Level Formatting

The level is formatted using `Level.to_string` (full name) or `Level.to_short_string` (3-char code). Access the short form in custom formatters by creating your own sink wrapper.

---

## Performance Considerations

### Level Checking (Fast Path)

Logs below the minimum level are discarded instantly:

```ocaml
(* If minimum level is Warning, this is basically free *)
Log.debug "Expensive trace" [...]  (* No computation happens *)
```

**Implication**: It's cheap to leave debug statements in production code.

### Sink Performance

- **Console**: Fast for low volume
- **File**: Depends on I/O subsystem
- **Multiple sinks**: Each event goes to all sinks

**Recommendation**: Use appropriate minimum levels to reduce volume

### Timestamp Caching

For high-frequency logging, millisecond timestamp caching is enabled by default:

```ocaml
(* Disable if you need unique timestamps for every log *)
Timestamp_cache.set_enabled false
```

---

## Troubleshooting

### Logs Not Appearing

1. Check logger is set:
   ```ocaml
   match Log.get_logger () with
   | None -> print_endline "Logger not set!"
   | Some _ -> ()
   ```

2. Check log level is enabled:
   ```ocaml
   if Log.is_enabled Level.Debug then
     print_endline "Debug enabled"
   ```

3. Check sink configuration:
   ```ocaml
   (* Is the sink minimum level satisfied? *)
   Configuration.write_to_file "app.log" ~min_level:Level.Error
   (* Won't log Information-level events *)
   ```

### Performance Issues

1. Lower the minimum level to reduce volume
2. Use hourly rotation instead of daily for very high volume
3. Use file sinks instead of console for high volume
4. Reduce enrichment/filtering complexity

---

## API Reference

### Main Configuration Functions

```ocaml
val create : unit -> t
(** Create a new configuration with default minimum level (Information) *)

val minimum_level : Level.t -> t -> t
(** Set the minimum log level *)

val verbose : t -> t
val debug : t -> t
val information : t -> t
val warning : t -> t
val error : t -> t
val fatal : t -> t
(** Convenience methods for common levels *)

val write_to_console :
  ?min_level:Level.t ->
  ?colors:bool ->
  ?stderr_threshold:Level.t ->
  ?output_template:string ->
  unit -> t -> t
(** Add console sink *)

val write_to_file :
  ?min_level:Level.t ->
  ?rolling:File_sink.rolling_interval ->
  ?output_template:string ->
  string -> t -> t
(** Add file sink *)

val write_to_null : ?min_level:Level.t -> unit -> t -> t
(** Add null sink (discard all) *)

val write_to : ?min_level:Level.t -> Composite_sink.sink_fn -> t -> t
(** Add a custom sink *)

val filter_by : Filter.t -> t -> t
(** Add a filter predicate *)

val filter_by_min_level : Level.t -> t -> t
(** Add minimum level filter *)

val enrich_with_property : string -> Yojson.Safe.t -> t -> t
(** Add an enriching property to all events *)

val enrich_with : (Log_event.t -> Log_event.t) -> t -> t
(** Add an enricher function *)

val build : t -> Logger.t
(** Build the logger from configuration *)
```

### Filter Functions

```ocaml
val level_filter : Level.t -> t
(** Filter by minimum level *)

val property_filter : string -> (Yojson.Safe.t -> bool) -> t
(** Filter by property value *)

val matching : string -> t
(** Filter that matches if property exists *)

val all : t list -> t
(** Combine filters with AND logic *)

val any : t list -> t
(** Combine filters with OR logic *)

val not_filter : t -> t
(** Negate a filter *)

val always_pass : t
(** Always include filter *)

val always_block : t
(** Always exclude filter *)
```

---

## See Also

- **README.md** - Feature overview
- **DEPLOYMENT.md** - Production deployment guide
- **examples/** - Working examples
