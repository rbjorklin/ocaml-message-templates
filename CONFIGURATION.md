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

## Fluent API

```ocaml
Configuration.create ()
  |> method1
  |> method2
  |> method3
  |> Configuration.build
```

### Conditional Configuration

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

```ocaml
Configuration.verbose config
Configuration.debug config
Configuration.information config
Configuration.warning config
Configuration.error config
Configuration.fatal config

Configuration.minimum_level Level.Information config
```

Set the minimum level first for fast-path filtering:

```ocaml
Configuration.create ()
|> Configuration.information
|> Configuration.write_to_console ()
```

Events below the minimum level are discarded instantly.

---

### Sinks (Output Destinations)

#### Console Sink

```ocaml
Configuration.write_to_console ()

Configuration.write_to_console
  ~colors:true
  ~stderr_threshold:Level.Warning
  ()

Configuration.write_to_console
  ~output_template:"{timestamp} [{level}] {message}"
  ()
```

Parameters: `colors`, `stderr_threshold`, `output_template`

#### File Sink

```ocaml
Configuration.write_to_file "app.log"

Configuration.write_to_file ~rolling:File_sink.Daily "logs/app.log"

Configuration.write_to_file ~rolling:File_sink.Hourly "logs/app.log"

Configuration.write_to_file ~rolling:File_sink.Infinite "logs/app.log"
```

Rolling strategies: `Infinite`, `Daily`, `Hourly`

#### JSON Sink

```ocaml
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

```ocaml
Configuration.write_to_null ()
```

#### Custom Sinks

```ocaml
let my_custom_sink =
  { Composite_sink.emit_fn = (fun event -> ...)
  ; flush_fn = (fun () -> ())
  ; close_fn = (fun () -> ()) }
in

Configuration.create ()
|> Configuration.write_to my_custom_sink
|> Configuration.build
```

#### Multiple Sinks

```ocaml
Configuration.create ()
|> Configuration.write_to_console ~colors:true ()
|> Configuration.write_to_file "app.log"
|> Configuration.write_to_file "errors.log" ~min_level:Level.Error
|> Configuration.build
```

Events go to all sinks that pass their filters.

---

### Per-Sink Configuration

```ocaml
|> Configuration.write_to_console ~min_level:Level.Debug ()
|> Configuration.write_to_file "errors.log" ~min_level:Level.Error
|> Configuration.write_to_file "app.log"
```

---

### Filtering

```ocaml
Configuration.filter_by_min_level Level.Warning config

Configuration.filter_by
  (Filter.property_filter "component" (function
    | `String "auth" -> true
    | _ -> false))
  config

Configuration.filter_by
  (Filter.all [
    Filter.level_filter Level.Warning;
    Filter.property_filter "service" (fun _ -> true)
  ])
  config

Configuration.filter_by
  (Filter.any [
    Filter.level_filter Level.Error;
    Filter.matching "retry_count"
  ])
  config

Configuration.filter_by
  (Filter.not_filter Filter.always_block)
  config
```

---

### Enrichment

```ocaml
Configuration.create ()
|> Configuration.enrich_with_property "version" (`String "1.2.3")
|> Configuration.enrich_with_property "environment" (`String "production")
|> Configuration.enrich_with (fun event -> event)
|> Configuration.build
```

---

## Common Configuration Patterns

### Development

```ocaml
let dev_logger () =
  Configuration.create ()
  |> Configuration.debug
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.enrich_with_property "env" (`String "dev")
  |> Configuration.build
```

### Production

```ocaml
let prod_logger () =
  Configuration.create ()
  |> Configuration.information
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

### Testing

```ocaml
let test_logger () =
  Configuration.create ()
  |> Configuration.write_to_null ()
  |> Configuration.build
```

### Staging

```ocaml
let staging_logger () =
  Configuration.create ()
  |> Configuration.warning
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

### Template Variables

- `{timestamp}` - Timestamp (RFC3339)
- `{level}` - Log level
- `{message}` - Rendered message

### Default Templates

Console: `[{timestamp} {level}] {message}`

File: `{timestamp} [{level}] {message}`

### Custom Examples

```ocaml
Configuration.write_to_console
  ~output_template:"[{level:short}] {message}"
  ()

Configuration.write_to_file
  ~output_template:"{timestamp} [{level}] {message}"
  "app.log"
```

Level formatting uses `Level.to_string` (full) or `Level.to_short_string` (3-char).

---

## Performance

Logs below the minimum level are discarded instantly:

```ocaml
Log.debug "Expensive trace" [...]  (* No computation if below min level *)
```

### Timestamp Caching

```ocaml
Timestamp_cache.set_enabled false
```

---

## Troubleshooting

### Logs Not Appearing

```ocaml
match Log.get_logger () with
| None -> print_endline "Logger not set!"
| Some _ -> ()
```

Check level:

```ocaml
if Log.is_enabled Level.Debug then
  print_endline "Debug enabled"
```

Check sink min_level:

```ocaml
Configuration.write_to_file "app.log" ~min_level:Level.Error
```

---

## API Reference

### Configuration

```ocaml
val create : unit -> t
val minimum_level : Level.t -> t -> t
val verbose : t -> t
val debug : t -> t
val information : t -> t
val warning : t -> t
val error : t -> t
val fatal : t -> t

val write_to_console :
  ?min_level:Level.t ->
  ?colors:bool ->
  ?stderr_threshold:Level.t ->
  ?output_template:string ->
  unit -> t -> t

val write_to_file :
  ?min_level:Level.t ->
  ?rolling:File_sink.rolling_interval ->
  ?output_template:string ->
  string -> t -> t

val write_to_null : ?min_level:Level.t -> unit -> t -> t
val write_to : ?min_level:Level.t -> Composite_sink.sink_fn -> t -> t
val filter_by : Filter.t -> t -> t
val filter_by_min_level : Level.t -> t -> t
val enrich_with_property : string -> Yojson.Safe.t -> t -> t
val enrich_with : (Log_event.t -> Log_event.t) -> t -> t
val build : t -> Logger.t
```

### Filter

```ocaml
val level_filter : Level.t -> t
val property_filter : string -> (Yojson.Safe.t -> bool) -> t
val matching : string -> t
val all : t list -> t
val any : t list -> t
val not_filter : t -> t
val always_pass : t
val always_block : t
```

---

## See Also

- **README.md** - Feature overview
- **DEPLOYMENT.md** - Production deployment guide
- **examples/** - Working examples
