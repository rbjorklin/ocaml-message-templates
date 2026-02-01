# OCaml Message Templates - Implementation TODO

## Previous Phase: Phase 6 - Complete with Timestamps (Production Ready) ✅

The core template PPX is complete and production-ready with:
- Compile-time template validation
- Automatic variable capture
- Format specifiers and operators
- Automatic timestamps in JSON output
- Full messagetemplates.org compliance

---

## Current Phase: Phase 7 - Logging Infrastructure

Implementing comprehensive logging infrastructure modeled after Serilog.

### Phase 1: Core Types and Log Levels ✅ COMPLETE

**Deliverables:**
- [x] `lib/level.ml` - Level type and operations (6 levels: Verbose, Debug, Information, Warning, Error, Fatal)
- [x] `lib/log_event.ml` - Log event type with timestamp, level, message, properties, exception
- [x] `test/test_level.ml` - Tests (6 tests passing)

### Phase 2: Sink Architecture ✅ COMPLETE

**Deliverables:**
- [x] `lib/sink.mli` - Sink interface
- [x] `lib/console_sink.ml` - Console output with colors and templates
- [x] `lib/file_sink.ml` - File output with rolling (Infinite, Daily, Hourly)
- [x] `lib/composite_sink.ml` - Multiple sinks support
- [x] `lib/null_sink.ml` - Testing sink
- [x] `test/test_sinks.ml` - Tests (6 tests passing)

### Phase 3: Logger Implementation ✅ COMPLETE

**Deliverables:**
- [x] `lib/logger.mli` - Logger interface with S, ENRICHER, and FILTER signatures
- [x] `lib/logger.ml` - Logger implementation with:
  - Level-based filtering (fast path)
  - Context properties support
  - Enricher pipeline
  - Multiple filters
  - Level-specific methods (verbose, debug, information, warning, error, fatal)
  - Flush and close operations
- [x] `test/test_logger.ml` - Tests (7 tests passing)

### Phase 4: Configuration API ✅ COMPLETE

**Deliverables:**
- [x] `lib/filter.ml` - Filter predicates:
  - `level_filter` - Filter by minimum level
  - `property_filter` - Filter by property value
  - `matching` - Filter by property existence
  - `all` - Combine filters with AND
  - `any` - Combine filters with OR
  - `not_filter` - Negate a filter
- [x] `lib/configuration.ml` - Configuration builder with fluent API:
  - `create ()` - Create new configuration
  - `minimum_level` / `verbose` / `debug` / `information` / `warning` / `error` / `fatal` - Set minimum level
  - `write_to_file` - Add file sink with optional rolling
  - `write_to_console` - Add console sink with colors
  - `write_to_null` - Add null sink
  - `enrich_with_property` - Add static property enricher
  - `filter_by_min_level` - Add minimum level filter
  - `create_logger` - Build logger from configuration
- [x] `test/test_configuration.ml` - Tests (13 tests passing)

### Phase 5: Global Log Module ✅ COMPLETE

**Deliverables:**
- [x] `lib/log_context.ml` - Ambient context for properties:
  - `push_property` / `pop_property` - Stack-based property management
  - `current_properties` - Get all current properties
  - `clear` - Clear all properties
  - `with_property` - Execute with temporary property (auto-pops)
  - `with_properties` - Execute with multiple temporary properties
  - `with_scope` - Create isolated scope
- [x] `lib/log.ml` - Global logger module:
  - `set_logger` / `get_logger` - Configure global logger
  - `close_and_flush` - Cleanup and close
  - `is_enabled` - Check if level is enabled
  - `write` - Write with explicit level
  - Level methods: `verbose`, `debug`, `information`, `warning`, `error`, `fatal`
  - `for_context` / `for_source` - Create contextual loggers
  - `flush` / `close` - Cleanup operations
- [x] `test/test_global_log.ml` - Tests (11 tests passing)

### Phase 6: PPX Extensions 🔄 IN PROGRESS

**Goals:**
- Extend PPX with level-aware extensions
- Add [%log.level "message"] syntax
- Support exception logging
- Compile-time level filtering

**Deliverables:**
- `ppx/ppx_log_levels.ml` - Level-aware PPX
- `test/test_ppx_levels.ml` - PPX tests
- Example usage files

### Phase 7: Integration and Documentation 📋 PENDING

**Goals:**
- Integrate all components
- Comprehensive test suite
- Documentation and examples
- Performance benchmarks

**Deliverables:**
- Complete test suite
- README updates
- Migration guide
- Performance comparison

---

## File Structure (Current)

```
lib/
├── level.ml                 # ✅ Log levels
├── log_event.ml            # ✅ Log event type
├── sink.mli                # ✅ Sink interface
├── console_sink.ml         # ✅ Console output
├── file_sink.ml            # ✅ File output with rolling
├── composite_sink.ml       # ✅ Multiple sinks
├── null_sink.ml            # ✅ Testing sink
├── logger.mli              # ✅ Logger interface
├── logger.ml               # ✅ Logger implementation
├── filter.ml               # ✅ Filter predicates
├── configuration.ml        # ✅ Configuration builder
├── log.ml                  # ✅ Global logger
├── log_context.ml          # ✅ Ambient context
├── types.ml                # Template AST types
├── template_parser.ml      # Angstrom parser
├── runtime_helpers.ml      # Type conversion
└── messageTemplates.ml     # Main library (updated)

ppx/
├── ppx_message_templates.ml     # Existing template PPX
└── ppx_log_levels.ml           # Level-aware logging PPX (future)

test/
├── test_level.ml           # ✅ Level tests (6 passing)
├── test_sinks.ml           # ✅ Sink tests (6 passing)
├── test_logger.ml          # ✅ Logger tests (7 passing)
├── test_configuration.ml   # ✅ Configuration tests (13 passing)
├── test_global_log.ml      # ✅ Global log tests (11 passing)
├── test_parser.ml          # Parser tests (5 passing)
└── test_ppx_comprehensive.ml   # PPX tests (8 passing)
```

---

## Test Status

**Total Tests**: 56 passing ✅
- Level Tests: 6/6 ✅
- Sink Tests: 6/6 ✅
- Logger Tests: 7/7 ✅
- Configuration Tests: 13/13 ✅
- Global Log Tests: 11/11 ✅
- Parser Tests: 5/5 ✅
- PPX Comprehensive Tests: 8/8 ✅

---

## Dependencies

**Current:**
- `yojson` - JSON output
- `eio` - Effects-based I/O
- `angstrom` - Parser combinators
- `ppxlib` - PPX framework
- `ptime` - Timestamp generation
- `unix` - Time retrieval
- `str` - String manipulation (for templates and file matching)

---

## Status

**Phase 1**: ✅ Complete (Core types)
**Phase 2**: ✅ Complete (Sinks)
**Phase 3**: ✅ Complete (Logger)
**Phase 4**: ✅ Complete (Configuration API)
**Phase 5**: ✅ Complete (Global Log module)
**Phase 6**: 🔄 In Progress (PPX Extensions)
**Overall**: Phase 7 of Logging Infrastructure Implementation
**Tests**: 56/56 passing
**Date**: 2026-01-31

---

## Global Log API Example

```ocaml
open Message_templates

(* Configure once at startup *)
let () =
  let logger =
    Configuration.create ()
    |> Configuration.debug
    |> Configuration.write_to_file ~rolling:File_sink.Daily "app.log"
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.enrich_with_property "Version" (`String "1.0.0")
    |> Configuration.create_logger
  in
  Log.set_logger logger

(* Use throughout application *)
let process_user user_id =
  Log_context.with_property "UserId" (`Int user_id) (fun () ->
    Log.information "Processing user" [];
    try
      (* ... work ... *)
      Log.debug "User processed successfully" []
    with e ->
      Log.error ~exn:e "Failed to process user" []
  )

(* Cleanup at shutdown *)
let () =
  Log.close_and_flush ()
```
