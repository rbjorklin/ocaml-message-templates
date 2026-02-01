# Logging Infrastructure Implementation Plan

## Executive Summary

This document outlines the implementation of a comprehensive logging infrastructure for the ocaml-message-templates library, modeled after Serilog's architecture. The goal is to provide a feature-complete logging system with log levels, configurable sinks, enrichers, filters, and a fluent configuration API.

**Key Missing Features from Current Implementation:**
1. Log levels (Verbose, Debug, Information, Warning, Error, Fatal)
2. Logger configuration and pipeline
3. Sink architecture for multiple outputs
4. Enrichment system for contextual properties
5. Filtering capabilities
6. Global/static logger support
7. Level-based filtering and minimum level configuration

---

## 1. Architecture Overview

### 1.1 Design Philosophy

The logging system follows Serilog's proven architecture adapted for OCaml:

```
┌─────────────────────────────────────────────────────────────┐
│  Application Code                                           │
│  Log.information "User {user} logged in"                    │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Level Check: Is Information >= MinimumLevel?               │
│  (Fast path - minimal overhead when disabled)              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Template Expansion (via existing PPX)                      │
│  - Generate string message                                  │
│  - Generate JSON structure                                  │
│  - Add @t timestamp, @m template, @l level                  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Enrichers (add contextual properties)                      │
│  - ThreadId, ProcessId, MachineName, etc.                   │
│  - Custom properties from LogContext                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Filters (predicate-based filtering)                        │
│  - Property-based filters                                   │
│  - Custom predicates                                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Sinks (write to destinations)                              │
│  - ConsoleSink (stdout/stderr with colors)                  │
│  - FileSink (rolling files)                                 │
│  - Multiple concurrent sinks                                │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Core Components

| Component | Responsibility | OCaml Module |
|-----------|---------------|--------------|
| Log Level | Define severity levels | `Level` |
| Log Event | Immutable log event structure | `Log_event` |
| Logger | Main logging interface | `Logger` |
| Sink | Write events to destinations | `Sink` |
| Enricher | Add contextual properties | `Enricher` |
| Filter | Conditionally drop events | `Filter` |
| Configuration | Build logger pipelines | `Configuration` |
| Global Log | Static logger access | `Log` |

---

## 2. Data Types

### 2.1 Log Level

```ocaml
(** Log levels ordered by severity (lowest to highest) *)
type level =
  | Verbose     (* 0 - Most detailed, rarely enabled *)
  | Debug       (* 1 - Internal system events *)
  | Information (* 2 - Normal operational messages (default) *)
  | Warning     (* 3 - Suspicious or degraded conditions *)
  | Error       (* 4 - Functionality unavailable *)
  | Fatal       (* 5 - System failure, needs immediate attention *)

val level_to_int : level -> int
val level_of_string : string -> level option
val level_to_string : level -> string
val level_to_short_string : level -> string  (* VRB, DBG, INF, WRN, ERR, FTL *)
val compare_level : level -> level -> int
```

### 2.2 Log Event

```ocaml
(** A single log event - immutable *)
type log_event = {
  timestamp : Ptime.t;                    (* Event timestamp *)
  level : Level.t;                        (* Severity level *)
  message_template : string;              (* Original template *)
  rendered_message : string;              (* Formatted message *)
  properties : (string * Yojson.Safe.t) list;  (* Structured properties *)
  exception_info : exn option;            (* Optional exception *)
}

val create_event :
  ?timestamp:Ptime.t ->
  ?exception_info:exn ->
  level:Level.t ->
  message_template:string ->
  rendered_message:string ->
  properties:(string * Yojson.Safe.t) list ->
  unit ->
  log_event
```

### 2.3 Logger Interface

```ocaml
(** Logger signature - main interface for logging *)
module type LOGGER = sig
  type t
  
  (** Core write method *)
  val write : t -> ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit
  
  (** Level checking *)
  val is_enabled : t -> Level.t -> bool
  
  (** Convenience methods for each level *)
  val verbose : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val debug : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val information : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val warning : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val error : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val fatal : t -> ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  
  (** Context enrichment *)
  val for_context : t -> string -> Yojson.Safe.t -> t
  val with_enricher : t -> (log_event -> log_event) -> t
  
  (** Sub-loggers for specific source types *)
  val for_source : t -> string -> t
end
```

---

## 3. Sink Architecture

### 3.1 Sink Interface

```ocaml
(** Sink signature - writes log events to destinations *)
module type SINK = sig
  type t
  
  (** Emit a log event to the sink *)
  val emit : t -> log_event -> unit
  
  (** Flush any buffered output *)
  val flush : t -> unit
  
  (** Close the sink and release resources *)
  val close : t -> unit
end
```

### 3.2 Built-in Sinks

```ocaml
(** Console sink with optional color output *)
module Console_sink : sig
  type t
  include SINK with type t := t
  
  val create :
    ?output_template:string ->
    ?colors:bool ->
    ?stderr_threshold:Level.t ->
    unit ->
    t
end

(** File sink with optional rolling *)
module File_sink : sig
  type t
  include SINK with type t := t
  
  type rolling_interval =
    | Infinite    (* Never roll *)
    | Daily
    | Hourly
    | By_size of int64  (* Roll when file exceeds size in bytes *)
  
  val create :
    path:string ->
    ?output_template:string ->
    ?rolling:rolling_interval ->
    ?max_files:int ->
    unit ->
    t
end

(** Composite sink - routes to multiple sinks *)
module Composite_sink : sig
  type t
  include SINK with type t := t
  
  val create : (module SINK with type t = 'a) list -> t
end

(** Null sink - discards all events (for testing/disabled) *)
module Null_sink : SINK
```

### 3.3 Output Templates

Output templates control text formatting:

```ocaml
(** Built-in output template properties *)
- {Timestamp}       - ISO 8601 timestamp
- {Level}           - Full level name (Verbose, Debug, etc.)
- {Level:u3}        - Uppercase 3-char (VRB, DBG, INF, WRN, ERR, FTL)
- {Level:w3}        - Lowercase 3-char (vrb, dbg, inf, wrn, err, ftl)
- {Message}         - Rendered message
- {Message:lj}      - Message with JSON formatting for non-strings
- {Exception}       - Exception details (if any)
- {Properties}      - All additional properties as JSON
- {Properties:j}    - Properties in JSON format
- {NewLine}         - Platform-specific newline

(** Default templates *)
val default_console_template : string
(* "[{Timestamp:HH:mm:ss} {Level:u3}] {Message}{NewLine}{Exception}" *)

val default_file_template : string
(* "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {Message}{NewLine}{Exception}" *)
```

---

## 4. Enrichers

### 4.1 Enricher Interface

```ocaml
(** Enricher signature - adds properties to log events *)
module type ENRICHER = sig
  type t
  
  (** Enrich a log event by adding properties *)
  val enrich : t -> log_event -> log_event
end

(** Common enrichers *)

(** Add thread ID *)
val thread_id_enricher : (module ENRICHER)

(** Add process ID *)
val process_id_enricher : (module ENRICHER)

(** Add machine name *)
val machine_name_enricher : (module ENRICHER)

(** Add timestamp (already handled by PPX, but available for enrichment) *)
val timestamp_enricher : (module ENRICHER)

(** Add static property *)
val property_enricher : string -> Yojson.Safe.t -> (module ENRICHER)

(** Composite enricher - applies multiple enrichers *)
val composite_enricher : (module ENRICHER) list -> (module ENRICHER)
```

### 4.2 Log Context (Ambient Context)

```ocaml
(** LogContext - ambient properties that flow across async boundaries *)
module Log_context : sig
  (** Push a property onto the context stack *)
  val push_property : string -> Yojson.Safe.t -> unit
  
  (** Pop the most recent property *)
  val pop_property : unit -> unit
  
  (** Get all current context properties *)
  val current_properties : unit -> (string * Yojson.Safe.t) list
  
  (** Clear all context properties *)
  val clear : unit -> unit
  
  (** Execute function with temporary property (auto-pops on exit) *)
  val with_property : string -> Yojson.Safe.t -> (unit -> 'a) -> 'a
end
```

---

## 5. Filters

### 5.1 Filter Interface

```ocaml
(** Filter signature - determines if an event should be logged *)
module type FILTER = sig
  type t
  
  (** Return true if the event should be included *)
  val is_included : t -> log_event -> bool
end

(** Common filter predicates *)

(** Filter by minimum level *)
val level_filter : Level.t -> (module FILTER)

(** Filter by property value *)
val property_filter : string -> (Yojson.Safe.t -> bool) -> (module FILTER)

(** Filter matching a specific property name *)
val matching : string -> (module FILTER)

(** Composite filter - all must pass *)
val all_filter : (module FILTER) list -> (module FILTER)

(** Composite filter - any can pass *)
val any_filter : (module FILTER) list -> (module FILTER)

(** Negate a filter *)
val not_filter : (module FILTER) -> (module FILTER)
```

---

## 6. Configuration API

### 6.1 Logger Configuration

```ocaml
(** Logger configuration - fluent builder API *)
module Configuration : sig
  type t
  
  (** Create a new configuration *)
  val create : unit -> t
  
  (** Set minimum level *)
  val minimum_level : Level.t -> t -> t
  
  (** Convenience methods for common levels *)
  val verbose : t -> t
  val debug : t -> t
  val information : t -> t
  val warning : t -> t
  val error : t -> t
  val fatal : t -> t
  
  (** Add a sink with optional minimum level override *)
  val write_to :
    ?min_level:Level.t ->
    (module SINK with type t = 'a) ->
    t ->
    t
  
  (** Add an enricher *)
  val enrich_with : (module ENRICHER with type t = 'a) -> t -> t
  
  (** Add a static property *)
  val enrich_with_property : string -> Yojson.Safe.t -> t -> t
  
  (** Add a filter *)
  val filter_by : (module FILTER with type t = 'a) -> t -> t
  
  (** Create the logger *)
  val create_logger : t -> (module LOGGER)
end
```

### 6.2 Configuration Example

```ocaml
let logger =
  Configuration.create ()
  |> Configuration.minimum_level Level.Debug
  |> Configuration.write_to (module Console_sink)
  |> Configuration.write_to ~min_level:Level.Warning (module File_sink)
       ~path:"logs/app-.log"
       ~rolling:File_sink.Daily
  |> Configuration.enrich_with (module Thread_id_enricher)
  |> Configuration.enrich_with_property "AppVersion" (`String "1.0.0")
  |> Configuration.filter_by (level_filter Level.Information)
  |> Configuration.create_logger
```

---

## 7. Global Logger (Log Module)

### 7.1 Static Logger API

```ocaml
(** Global logger - static access like Serilog.Log *)
module Log : sig
  (** The global logger instance *)
  val mutable logger : (module LOGGER)
  
  (** Set the global logger *)
  val set_logger : (module LOGGER) -> unit
  
  (** Close and flush the global logger *)
  val close_and_flush : unit -> unit
  
  (** Check if a level is enabled *)
  val is_enabled : Level.t -> bool
  
  (** Write with explicit level *)
  val write : ?exn:exn -> Level.t -> string -> (string * Yojson.Safe.t) list -> unit
  
  (** Level-specific methods *)
  val verbose : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val debug : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val information : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val warning : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val error : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  val fatal : ?exn:exn -> string -> (string * Yojson.Safe.t) list -> unit
  
  (** Create contextual logger *)
  val for_context : string -> Yojson.Safe.t -> (module LOGGER)
  val for_source : string -> (module LOGGER)
end
```

### 7.2 Usage Example

```ocaml
(* Configure once at application startup *)
let () =
  let logger =
    Configuration.create ()
    |> Configuration.write_to (module Console_sink)
    |> Configuration.create_logger
  in
  Log.set_logger logger

(* Use throughout application *)
let process_user user_id =
  Log.information "Processing user {user_id}" ["user_id", `Int user_id];
  try
    (* ... work ... *)
    Log.debug "User {user_id} processed successfully" ["user_id", `Int user_id]
  with
  | e ->
    Log.error ~exn:e "Failed to process user {user_id}" ["user_id", `Int user_id]

(* Close at application shutdown *)
let () =
  Log.close_and_flush ()
```

---

## 8. PPX Integration

### 8.1 Level-Aware PPX Extensions

Extend the existing PPX to support level-aware logging:

```ocaml
(** Level-specific PPX extensions *)
[%log.verbose "Detailed: {variable}"]
[%log.debug "Debug info: {variable}"]
[%log.information "User {user} logged in"]
[%log.warning "Slow query: {query}"]
[%log.error ~exn "Failed: {error}"]
[%log.fatal "System failure: {reason}"]

(** These expand to: *)
(* Log.verbose ~exn:None "Detailed: %s" ["variable", `String (string_of_value variable)] *)
```

### 8.2 Configuration-Aware PPX

The PPX should be aware of the minimum log level at compile time for zero-cost abstractions:

```ocaml
(* If minimum level is Information, Debug logs are compiled to no-ops *)
[%log.debug "This will not appear in compiled output"]
(* Expands to: () - no runtime cost *)
```

---

## 9. Implementation Phases

### Phase 1: Core Types and Log Levels (Week 1)

**Goals:**
- Define Level.t type with proper ordering
- Implement log_event type
- Add level comparison and conversion functions

**Deliverables:**
- `lib/level.ml` - Level type and operations
- `lib/log_event.ml` - Log event type
- Tests for level operations

### Phase 2: Sink Architecture (Week 2)

**Goals:**
- Define SINK signature
- Implement Console_sink with colors and templates
- Implement File_sink with rolling
- Implement Composite_sink and Null_sink

**Deliverables:**
- `lib/sink.mli` - Sink interface
- `lib/console_sink.ml` - Console output
- `lib/file_sink.ml` - File output with rolling
- Tests for sink operations

### Phase 3: Logger Implementation (Week 3)

**Goals:**
- Define LOGGER signature
- Implement Logger module with level checking
- Add ForContext support for contextual logging
- Implement enrichment pipeline

**Deliverables:**
- `lib/logger.mli` - Logger interface
- `lib/logger.ml` - Logger implementation
- `lib/enricher.ml` - Enricher system
- Tests for logger functionality

### Phase 4: Configuration API (Week 4)

**Goals:**
- Implement Configuration module with fluent API
- Add support for minimum level
- Support multiple sinks with level overrides
- Support enrichers and filters

**Deliverables:**
- `lib/configuration.ml` - Configuration builder
- `lib/filter.ml` - Filter predicates
- Integration tests

### Phase 5: Global Log Module (Week 5)

**Goals:**
- Implement Log module for global access
- Add LogContext for ambient properties
- Implement thread-safe context storage

**Deliverables:**
- `lib/log.ml` - Global logger
- `lib/log_context.ml` - Ambient context
- Tests for global logging

### Phase 6: PPX Extensions (Week 6)

**Goals:**
- Extend PPX with level-aware extensions
- Add [%log.level "message"] syntax
- Support exception logging
- Compile-time level filtering

**Deliverables:**
- `ppx/ppx_log_levels.ml` - Level-aware PPX
- Tests for PPX expansions
- Example usage files

### Phase 7: Integration and Documentation (Week 7-8)

**Goals:**
- Integrate all components
- Comprehensive test suite
- Documentation and examples
- Performance benchmarks

**Deliverables:**
- Complete test suite
- README updates
- Migration guide
- Performance comparison with Serilog-style usage

---

## 10. File Structure

```
lib/
├── level.ml                 # Log levels
├── log_event.ml            # Log event type
├── sink.mli                # Sink interface
├── console_sink.ml         # Console output
├── file_sink.ml            # File output
├── logger.mli              # Logger interface
├── logger.ml               # Logger implementation
├── enricher.ml             # Enrichment system
├── filter.ml               # Filtering predicates
├── configuration.ml        # Configuration builder
├── log_context.ml          # Ambient context
├── log.ml                  # Global logger
└── messageTemplates.ml     # Main library module

ppx/
├── ppx_message_templates.ml     # Existing template PPX
└── ppx_log_levels.ml           # Level-aware logging PPX

test/
├── test_level.ml           # Level tests
├── test_sinks.ml           # Sink tests
├── test_logger.ml          # Logger tests
├── test_configuration.ml   # Configuration tests
├── test_log_context.ml     # Context tests
└── test_ppx_levels.ml      # PPX tests

examples/
├── logging_basic.ml        # Basic logging example
├── logging_advanced.ml     # Advanced features
└── logging_configuration.ml # Configuration examples
```

---

## 11. Dependencies

**New Dependencies Required:**

```dune
(depends
  (ocaml (>= 5.4.0))
  (ppxlib (>= 0.35.0))
  (angstrom (>= 0.15.0))
  (yojson (>= 2.0.0))
  (eio (>= 1.0))
  (ptime (>= 1.0))
  (fmt (>= 0.9))           (* For pretty printing and colors *)
  (lwt (>= 5.6))           (* For async context, optional *)
  (alcotest :with-test)
  (qcheck :with-test))
```

---

## 12. API Comparison with Serilog

| Serilog (C#) | OCaml Equivalent | Notes |
|--------------|------------------|-------|
| `LogEventLevel` | `Level.t` | Same 6 levels |
| `LogEvent` | `log_event` | Immutable record |
| `ILogger` | `LOGGER` signature | Interface via module type |
| `ILogEventSink` | `SINK` signature | Pluggable outputs |
| `ILogEventEnricher` | `ENRICHER` signature | Context properties |
| `LoggerConfiguration` | `Configuration` | Fluent builder API |
| `Log.Logger` | `Log.logger` | Global instance |
| `Log.Information()` | `Log.information` | Level methods |
| `Log.ForContext()` | `Log.for_context` | Contextual logging |
| `LogContext.PushProperty()` | `Log_context.push_property` | Ambient properties |
| `MinimumLevel.Is()` | `Configuration.minimum_level` | Level filtering |
| `WriteTo.Console()` | `Configuration.write_to (module Console_sink)` | Sink configuration |

---

## 13. Performance Considerations

### 13.1 Zero-Cost Abstractions

- Level checks at the beginning of the pipeline (fast path)
- PPX compile-time level filtering for disabled levels
- Lazy evaluation of expensive enrichers

### 13.2 Concurrent Safety

- Immutable log events (share safely)
- Lock-free sink writes where possible
- Thread-local storage for LogContext
- Eio-based async I/O for file sinks

### 13.3 Memory Efficiency

- Reuse format strings (compiled by PPX)
- Avoid intermediate string allocations
- Batch writes to file sinks
- Ring buffer for high-throughput scenarios

---

## 14. Example Usage

### 14.1 Basic Usage

```ocaml
open Message_templates

let () =
  (* Configure logging *)
  let logger =
    Configuration.create ()
    |> Configuration.write_to (module Console_sink)
    |> Configuration.create_logger
  in
  Log.set_logger logger;
  
  (* Log messages *)
  let user = "alice" in
  Log.information "User {user} logged in" ["user", `String user];
  
  (* Cleanup *)
  Log.close_and_flush ()
```

### 14.2 With PPX

```ocaml
open Message_templates

let () =
  Log.set_logger (Configuration.create () 
    |> Configuration.write_to (module Console_sink)
    |> Configuration.create_logger);
  
  let username = "alice" in
  let ip = "192.168.1.1" in
  
  [%log.information "User {username} logged in from {ip}"];
  
  Log.close_and_flush ()
```

### 14.3 Advanced Configuration

```ocaml
open Message_templates

let () =
  let logger =
    Configuration.create ()
    |> Configuration.minimum_level Level.Debug
    |> Configuration.write_to 
         (module Console_sink)
         ~output_template:"[{Timestamp:HH:mm:ss} {Level:u3}] {Message}{NewLine}{Exception}"
    |> Configuration.write_to ~min_level:Level.Warning
         (module File_sink)
         ~path:"logs/app-.log"
         ~rolling:Daily
    |> Configuration.enrich_with_property "Environment" (`String "Production")
    |> Configuration.enrich_with (module Thread_id_enricher)
    |> Configuration.filter_by (property_filter "UserId" (fun _ -> true))
    |> Configuration.create_logger
  in
  
  Log.set_logger logger;
  
  (* Use context properties *)
  Log_context.with_property "RequestId" (`String "abc-123") (fun () ->
    Log.information "Processing request" []
  );
  
  Log.close_and_flush ()
```

---

## 15. Testing Strategy

### 15.1 Unit Tests

- Level ordering and comparison
- Sink write operations
- Enricher transformations
- Filter predicates
- Configuration builder

### 15.2 Integration Tests

- End-to-end logging pipeline
- Multiple sink coordination
- LogContext flow
- File rolling behavior
- Concurrent access

### 15.3 PPX Tests

- Level-specific expansions
- Compile-time filtering
- Exception logging syntax
- Template integration

---

## 16. Future Enhancements

### 16.1 Additional Sinks

- HTTP sink (send to log aggregators)
- Database sink (SQL/NoSQL)
- Message queue sink (RabbitMQ, Kafka)
- Metrics sink (Prometheus, StatsD)

### 16.2 Advanced Features

- Structured log correlation (request tracing)
- Sampling (log only N% of events)
- Buffering and batching
- Async/await logging for Eio
- Log shipping with backpressure

### 16.3 Configuration Sources

- JSON/YAML configuration files
- Environment variable configuration
- OCaml expression-based config

---

## 17. Conclusion

This implementation plan provides a roadmap for adding comprehensive logging infrastructure to the ocaml-message-templates library. The design follows Serilog's proven patterns while adapting them to OCaml's type system and functional programming paradigm.

**Estimated Timeline:** 8 weeks for production-ready implementation
**Priority:** Sink architecture and logger interface are critical path items
**Risk:** PPX complexity for level-aware extensions; mitigated by keeping template PPX separate

The result will be a feature-complete, type-safe, high-performance logging library for OCaml that rivals Serilog in functionality while leveraging OCaml's strengths in compile-time safety and runtime performance.
