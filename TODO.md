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

**Goals:**
- [x] Define Level.t type with proper ordering
- [x] Implement log_event type
- [x] Add level comparison and conversion functions
- [x] Write tests for level operations

**Deliverables:**
- [x] `lib/level.ml` - Level type and operations
- [x] `lib/log_event.ml` - Log event type
- [x] `test/test_level.ml` - Tests (6 tests passing)

### Phase 2: Sink Architecture ✅ COMPLETE

**Goals:**
- [x] Define SINK signature
- [x] Implement Console_sink with colors and templates
- [x] Implement File_sink with rolling support
- [x] Implement Composite_sink
- [x] Implement Null_sink
- [x] Add tests for sinks

**Deliverables:**
- [x] `lib/sink.mli` - Sink interface
- [x] `lib/console_sink.ml` - Console output with colors
- [x] `lib/file_sink.ml` - File output with rolling (Infinite, Daily, Hourly)
- [x] `lib/composite_sink.ml` - Multiple sinks support
- [x] `lib/null_sink.ml` - Testing sink
- [x] `test/test_sinks.ml` - Tests (6 tests passing)

### Phase 3: Logger Implementation 🔄 IN PROGRESS

**Goals:**
- Define LOGGER signature
- Implement Logger module with level checking
- Add ForContext support for contextual logging
- Implement enrichment pipeline

**Deliverables:**
- `lib/logger.mli` - Logger interface
- `lib/logger.ml` - Logger implementation
- `lib/enricher.ml` - Enricher system
- `test/test_logger.ml` - Tests

### Phase 4: Configuration API 📋 PENDING

**Goals:**
- Implement Configuration module with fluent API
- Add support for minimum level
- Support multiple sinks with level overrides
- Support enrichers and filters

**Deliverables:**
- `lib/configuration.ml` - Configuration builder
- `lib/filter.ml` - Filter predicates
- `test/test_configuration.ml` - Tests

### Phase 5: Global Log Module 📋 PENDING

**Goals:**
- Implement Log module for global access
- Add LogContext for ambient properties
- Implement thread-safe context storage

**Deliverables:**
- `lib/log.ml` - Global logger
- `lib/log_context.ml` - Ambient context
- `test/test_log_context.ml` - Tests

### Phase 6: PPX Extensions 📋 PENDING

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
├── logger.mli              # Logger interface (in progress)
├── logger.ml               # Logger implementation (pending)
├── enricher.ml             # Enrichment system (pending)
├── filter.ml               # Filtering predicates (pending)
├── configuration.ml        # Configuration builder (pending)
├── log_context.ml          # Ambient context (pending)
├── log.ml                  # Global logger (pending)
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
├── test_parser.ml          # Parser tests (5 passing)
└── test_ppx_comprehensive.ml   # PPX tests (8 passing)
```

---

## Test Status

**Total Tests**: 25 passing ✅
- Level Tests: 6/6 ✅
- Sink Tests: 6/6 ✅
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

**New (for logging infrastructure):**
- `fmt` (>= 0.9) - For pretty printing and colors (optional)

---

## Status

**Phase 1**: ✅ Complete (Level and Log_event modules)
**Phase 2**: ✅ Complete (All sinks implemented and tested)
**Overall**: Phase 7 of Logging Infrastructure Implementation
**Tests**: 25/25 passing
**Date**: 2026-01-31
