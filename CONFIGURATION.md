# Message Templates Configuration Guide

Complete guide to configuring loggers in Message Templates.

## Quick Start

### Minimal Setup (Console Only)

```ocaml
open Message_templates

let () =
  Configuration.create ()
  |> Configuration.write_to_console ()
  |> Configuration.create_logger
  |> Log.set_logger;
  Log.information "Application started" []
```

### Production Setup (File + Console)

```ocaml
let () =
  Configuration.create ()
  |> Configuration.information  (* Set minimum level *)
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.write_to_file ~rolling:File_sink.Daily "app.log"
  |> Configuration.create_logger
  |> Log.set_logger;
  Log.information "Application started" []
```

### High-Volume Logging

```ocaml
let () =
  Configuration.create ()
  |> Configuration.warning  (* Only warnings and above *)
  |> Configuration.write_to_file ~rolling:File_sink.Hourly "app.log"
  |> Configuration.write_to_file ~rolling:File_sink.Infinite "errors.log"
      ~min_level:Level.Error
  |> Configuration.create_logger
  |> Log.set_logger
```

---

## Fluent API Overview

The configuration API uses a **fluent builder pattern** where each method returns a modified configuration:

```ocaml
Configuration.create ()
  |> method1
  |> method2
  |> method3
  |> Configuration.create_logger
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
  |> Configuration.create_logger
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
  ["var1", `String v1; "var2", `String v2; "var3", `String v3]
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
  ~output_template:"{@t:u} [{@l:u3}] {@m}"
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
  "app-{date}.log"

(* With hourly rotation for high-volume apps *)
Configuration.write_to_file
  ~rolling:File_sink.Hourly
  "app-{date}-{hour}.log"

(* By size (100MB max per file) *)
Configuration.write_to_file
  ~rolling:(File_sink.By_size (100 * 1024 * 1024))
  "app.log"

(* JSON structured logging *)
Configuration.write_to_file
  ~output_template:"{@t} {@mt} {...}"
  "app.json"
```

**Rolling Strategies:**
- `Infinite`: Single file, no rotation
- `Daily`: New file each day
- `Hourly`: New file each hour  
- `By_size max_bytes`: New file when size exceeded

**Best Practice**: Use `Daily` for most applications

#### Null Sink

Discard all logs (useful for testing):

```ocaml
Configuration.write_to_null ()
```

#### Multiple Sinks

Add multiple sinks to output to multiple destinations:

```ocaml
Configuration.create ()
|> Configuration.write_to_console ~colors:true ()
|> Configuration.write_to_file "app.log"
|> Configuration.write_to_file "errors.log" ~min_level:Level.Error
|> Configuration.create_logger
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
Configuration.with_filter
  (Filter.by_level Level.Warning)
  config
```

#### Filter by Property

Only log events with specific properties:

```ocaml
Configuration.with_filter
  (Filter.has_property "component" (`String "auth"))
  config
```

#### Combine Filters with AND/OR/NOT

```ocaml
(* All of these must match *)
Configuration.with_filter
  (Filter.all [
    Filter.by_level Level.Warning;
    Filter.has_property "service" (`String "api")
  ])
  config

(* At least one must match *)
Configuration.with_filter
  (Filter.any [
    Filter.by_level Level.Error;
    Filter.has_property "retry_count" (`Int 3)
  ])
  config

(* Invert a filter *)
Configuration.with_filter
  (Filter.not (Filter.has_property "skip_logging" (`Bool true)))
  config
```

---

### Enrichment

Add properties automatically to all log events:

```ocaml
Configuration.create ()
|> Configuration.with_property "version" (`String "1.2.3")
|> Configuration.with_property "environment" (`String "production")
|> Configuration.with_enricher (fun event ->
    (* Add timestamp of log creation *)
    event
)
|> Configuration.create_logger
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
  |> Configuration.with_property "env" (`String "dev")
  |> Configuration.create_logger
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
  |> Configuration.with_property "env" (`String "prod")
  |> Configuration.with_property "hostname" (`String (Unix.gethostname ()))
  |> Configuration.create_logger
```

### Testing Configuration

```ocaml
let test_logger () =
  Configuration.create ()
  |> Configuration.write_to_null ()  (* Discard all logs *)
  |> Configuration.create_logger
```

### Staging Configuration

```ocaml
let staging_logger () =
  Configuration.create ()
  |> Configuration.warning          (* Less verbose than dev *)
  |> Configuration.write_to_console ()
  |> Configuration.write_to_file "/var/log/app/staging.log"
  |> Configuration.with_property "env" (`String "staging")
  |> Configuration.create_logger
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
  |> Configuration.with_property "env" (`String env)
  |> Configuration.create_logger
```

### Per-Module Loggers

```ocaml
(* Each module has its own configuration *)
module Auth = struct
  let logger =
    Configuration.create ()
    |> Configuration.information
    |> Configuration.write_to_file "auth.log"
    |> Configuration.with_property "module" (`String "auth")
    |> Configuration.create_logger
end

module Api = struct
  let logger =
    Configuration.create ()
    |> Configuration.debug  (* More verbose for API *)
    |> Configuration.write_to_file "api.log"
    |> Configuration.with_property "module" (`String "api")
    |> Configuration.create_logger
end
```

### Conditional Enrichment

```ocaml
let make_logger ~user_id ~request_id =
  let config = Configuration.create ()
  in
  let config = match user_id with
    | Some uid -> Configuration.with_property "user_id" (`String uid) config
    | None -> config
  in
  let config = match request_id with
    | Some req -> Configuration.with_property "request_id" (`String req) config
    | None -> config
  in
  config
  |> Configuration.write_to_file "app.log"
  |> Configuration.create_logger
```

---

## Output Templates

Control the format of log output with templates:

### Template Variables

- `@t` - Timestamp (RFC3339)
- `@mt` - Message template (with placeholders)
- `@m` - Rendered message (with values)
- `@l` - Log level
- Custom fields from properties

### Examples

```ocaml
(* Default *)
"{@t} [{@l}] {@m}"

(* Compact *)
"[{@l:u3}] {@m}"

(* Verbose with properties *)
"{@t} [{@l}] [{component}] {@m}"

(* JSON (for structured logging) *)
"{@t} {@mt} {@l} {...}"
```

### Log Level Format Specifiers

- `{@l}` - Full name: "Information"
- `{@l:u}` - Uppercase: "INFORMATION"
- `{@l:l}` - Lowercase: "information"
- `{@l:u3}` - Uppercase 3-char: "INF"

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

- **Console**: ~50k events/sec
- **File**: ~10k events/sec (depends on I/O)
- **Multiple sinks**: Each event goes to all sinks

**Recommendation**: Use appropriate minimum levels to reduce volume

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
2. Use hourly rotation instead of daily
3. Use file sinks instead of console for high volume
4. Reduce enrichment/filtering complexity

---

## API Reference

### Main Configuration Functions

```ocaml
val create : unit -> t
(** Create a new configuration *)

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
  ?colors:bool ->
  ?stderr_threshold:Level.t ->
  ?output_template:string ->
  unit -> t -> t
(** Add console sink *)

val write_to_file :
  ?min_level:Level.t ->
  ?rolling:File_sink.rolling ->
  ?output_template:string ->
  string -> t -> t
(** Add file sink *)

val write_to_null : unit -> t -> t
(** Add null sink (discard all) *)

val with_filter : Filter.t -> t -> t
(** Add a filter *)

val with_property : string -> Yojson.Safe.t -> t -> t
(** Add an enriching property *)

val with_enricher : (Log_event.t -> Log_event.t) -> t -> t
(** Add an enricher function *)

val create_logger : t -> Logger.t
(** Build the logger from configuration *)
```

---

## See Also

- **README.md** - Feature overview
- **DEPLOYMENT.md** - Production deployment guide
- **examples/** - Working examples
