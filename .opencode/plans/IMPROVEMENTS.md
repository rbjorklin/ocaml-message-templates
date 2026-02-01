# OCaml Message Templates - Implementation Improvement Plan

This document outlines a comprehensive plan to address identified gaps and enhancement opportunities in the OCaml Message Templates library.

**Current Status**: Production-ready with 59 passing tests
**Target Status**: Production-ready with comprehensive coverage, improved safety, and enhanced features

---

## Executive Summary

### Critical Issues to Address
1. **Json_sink completely untested** - Core structured logging feature lacks coverage
2. **Unsafe `Obj` module usage** - Potential breakage with compiler updates
3. **Missing parser error tests** - No validation of graceful error handling
4. **No async I/O support** - Limits high-throughput production use cases

### Implementation Phases
- **Phase 1**: Critical Safety & Testing (2-3 weeks)
- **Phase 2**: Performance & Architecture (3-4 weeks)
- **Phase 3**: Features & Enhancements (4-6 weeks)
- **Phase 4**: Documentation & Polish (2 weeks)

**Total Estimated Effort**: 11-15 weeks for one developer, 6-8 weeks for two developers working in parallel

---

## Phase 1: Critical Safety & Testing

### 1.1 Add Comprehensive Json_sink Testing

**Priority**: Critical
**Effort**: 3-4 days
**Files**: `test/test_json_sink.ml` (new)

#### Implementation Steps

1. **Create test file** at `test/test_json_sink.ml`:
   ```ocaml
   open Message_templates
   open Alcotest
   
   let test_json_sink_basic () =
     (* Create temp file, write events, verify JSON structure *)
     
   let test_json_sink_clef_format () =
     (* Verify @t, @mt, @m, @l fields present and correctly formatted *)
     
   let test_json_sink_properties () =
     (* Verify custom properties appear in JSON output *)
     
   let test_json_sink_multiple_events () =
     (* Verify NDJSON format - one event per line *)
     
   let test_json_sink_flush_close () =
     (* Verify proper file handling *)
   ```

2. **Test scenarios to cover**:
   - Single event with all CLEF fields
   - Multiple events in sequence
   - Events with various property types (string, int, float, bool, null)
   - Events with special characters in messages
   - Proper file flushing and closing
   - JSON structure validation (parse and verify)

3. **Add to test/dune**:
   ```dune
   (test
    (name test_json_sink)
    (libraries message-templates alcotest yojson))
   ```

#### Success Criteria
- [ ] 8-10 comprehensive tests for Json_sink
- [ ] All CLEF fields validated
- [ ] Multiple event scenarios tested
- [ ] 100% line coverage for Json_sink module

---

### 1.2 Replace Unsafe `Obj` Module Usage

**Priority**: Critical
**Effort**: 1 week
**Files**: `lib/runtime_helpers.ml`, `ppx/code_generator.ml`

#### Current Problem
The `Obj` module is used for runtime type inspection:
```ocaml
(* Current implementation in runtime_helpers.ml *)
let to_string (x : 'a) : string =
  let obj = Obj.repr x in
  if Obj.is_int obj then
    string_of_int (Obj.obj obj)
  else if Obj.is_block obj then
    match Obj.tag obj with
    | 252 -> (Obj.obj x : string)  (* String tag - fragile! *)
    | 253 -> string_of_float (Obj.obj x : float)
    | _ -> "<block>"
  else
    "<unknown>"
```

#### Proposed Solutions

**Option A: Compile-time type information via PPX** (Recommended)
- Modify PPX to generate type-specific conversion functions
- Pass type information from PPX to generated code
- Eliminates need for runtime type inspection

**Option B: Use `Type_repr` library**
- Add dependency on `type_repr` or similar library
- Provides safer runtime type representation
- Less invasive change but adds dependency

**Option C: Explicit type witnesses**
- Define a type witness GADT for supported types
- Require users to provide type witnesses for custom types
- Most type-safe but changes API

#### Implementation Plan (Option A)

1. **Modify PPX to track types**:
   ```ocaml
   (* In ppx/code_generator.ml *)
   let generate_conversion_code ~loc (expr : expression) (typ : core_type option) =
     match typ with
     | Some [%type: string] -> [%expr `String [%e expr]]
     | Some [%type: int] -> [%expr `Int [%e expr]]
     | Some [%type: float] -> [%expr `Float [%e expr]]
     | Some [%type: bool] -> [%expr `Bool [%e expr]]
     | _ -> (* fallback to runtime helper with warning *)
   ```

2. **Update scope_analyzer** to capture type information:
   ```ocaml
   type binding = {
     name: string;
     typ: core_type option;  (* Extract from pattern/type annotation *)
   }
   ```

3. **Create typed conversion module**:
   ```ocaml
   (* lib/runtime_helpers.ml - new safe versions *)
   module Safe = struct
     let string_to_json s = `String s
     let int_to_json i = `Int i
     let float_to_json f = `Float f
     let bool_to_json b = `Bool b
     let int64_to_json i = `Intlit (Int64.to_string i)
     let list_to_json f lst = `List (List.map f lst)
   end
   ```

4. **Gradual migration path**:
   - Keep existing `Obj`-based code for backward compatibility
   - Add `[@@deprecated]` annotation
   - Generate compile-time conversions where type info available
   - Fall back to runtime only when necessary

#### Success Criteria
- [ ] PPX generates type-specific conversions for common types
- [ ] No `Obj` module usage in hot paths
- [ ] Backward compatibility maintained
- [ ] Performance maintained or improved
- [ ] Tests pass with new implementation

---

### 1.3 Add Parser Error Case Tests

**Priority**: High
**Effort**: 2-3 days
**Files**: `test/test_parser.ml`

#### Implementation Steps

1. **Extend test_parser.ml** with error scenarios:
   ```ocaml
   let test_unmatched_open_brace () =
     match parse_template "Hello {name" with
     | Ok _ -> fail "Should have failed with unmatched brace"
     | Error msg -> check string "Error message mentions brace" true
       (String.contains msg '{')
   
   let test_unmatched_close_brace () =
     match parse_template "Hello }name" with
     | Ok _ -> fail "Should have failed"
     | Error _ -> ()
   
   let test_invalid_hole_name () =
     (* Test holes with invalid characters *)
     
   let test_empty_hole_name () =
     (* Test {} - should this be valid or error? *)
     
   let test_invalid_format_specifier () =
     (* Test malformed format specs *)
     
   let test_nested_braces () =
     (* Test {{ {name} }} scenarios *)
   ```

2. **Define expected behavior for edge cases**:
   - Unmatched `{` - should error with position
   - Unmatched `}` - should error or treat as literal?
   - Empty hole `{}` - error or valid?
   - Invalid characters in hole names - error
   - Malformed format specifiers - error

3. **Verify error messages** are helpful:
   - Include position in template
   - Suggest fix where possible
   - Clear description of what went wrong

#### Success Criteria
- [ ] 10+ error case tests
- [ ] All edge cases documented
- [ ] Error messages are helpful and tested
- [ ] Parser behavior consistent and documented

---

### 1.4 Add Alignment Specifier Tests

**Priority**: High
**Effort**: 1-2 days
**Files**: `test/test_parser.ml`, `ppx/code_generator.ml`

#### Implementation Steps

1. **Verify alignment support in parser**:
   ```ocaml
   let test_positive_alignment () =
     let result = parse_template "{name,10}" in
     (* Verify alignment = Some (false, 10) *)
   
   let test_negative_alignment () =
     let result = parse_template "{name,-10}" in
     (* Verify alignment = Some (true, 10) *)
   ```

2. **Add code generation for alignment**:
   ```ocaml
   (* In code_generator.ml - if not already implemented *)
   let apply_alignment ~loc expr (is_negative, width) =
     if is_negative then
       [%expr Printf.sprintf "%-*s" [%e eint ~loc width] [%e expr]]
     else
       [%expr Printf.sprintf "%*s" [%e eint ~loc width] [%e expr]]
   ```

3. **Test end-to-end alignment**:
   ```ocaml
   let name = "Alice" in
   let msg, _ = [%template "Name: {name,10} |"] in
   (* Verify msg = "Name:      Alice |" *)
   
   let msg, _ = [%template "Name: {name,-10} |"] in
   (* Verify msg = "Name: Alice      |" *)
   ```

#### Success Criteria
- [ ] Parser correctly parses alignment specifiers
- [ ] Code generator produces aligned output
- [ ] Both positive and negative alignment tested
- [ ] Integration with format specifiers works

---

### 1.5 Convert test_escape.ml to Proper Test

**Priority**: Medium
**Effort**: 1 day
**Files**: `test/test_escape.ml`

#### Implementation Steps

1. **Rewrite as Alcotest**:
   ```ocaml
   open Alcotest
   open Message_templates
   
   let test_double_left_brace () =
     let result = Template_parser.parse_template "{{" in
     (* Verify parses as literal "{" *)
   
   let test_double_right_brace () =
     let result = Template_parser.parse_template "}}" in
     (* Verify parses as literal "}" *)
   
   let test_mixed_escapes () =
     let result = Template_parser.parse_template "{{ {name} }}" in
     (* Verify correct structure *)
   
   let () =
     run "Escape Tests" [
       "braces", [
         test_case "Double left" `Quick test_double_left_brace;
         test_case "Double right" `Quick test_double_right_brace;
         test_case "Mixed" `Quick test_mixed_escapes;
       ];
     ]
   ```

2. **Add to test/dune** as proper test executable

#### Success Criteria
- [ ] Converted to Alcotest format
- [ ] All escape scenarios tested
- [ ] Integrated into test suite

---

## Phase 2: Performance & Architecture

### 2.1 Implement Async/Batching Sink Support

**Priority**: High
**Effort**: 2-3 weeks
**Files**: New `lib/async_sink.ml`, `lib/batching_sink.ml`, modifications to `lib/logger.ml`

#### Design Goals
- Support high-throughput logging without blocking application
- Configurable batching strategies (size-based, time-based)
- Backpressure handling for slow sinks
- Memory-efficient buffering

#### Implementation Plan

1. **Create Async Sink Wrapper** (`lib/async_sink.ml`):
   ```ocaml
   module Async_sink : sig
     type t
     val create : 
       ?max_queue_size:int ->
       ?overflow_strategy:[`Drop | `Block | `Raise] ->
       Sink.S -> t
     val emit : t -> Log_event.t -> unit  (* Non-blocking *)
     val flush : t -> unit Lwt.t
     val close : t -> unit Lwt.t
   end = struct
     type t = {
       queue: Log_event.t Queue.t;
       worker: unit Lwt.t;
       max_size: int;
       strategy: [`Drop | `Block | `Raise];
       inner: Sink.S;
     }
     
     let emit t event =
       if Queue.length t.queue >= t.max_size then
         match t.strategy with
         | `Drop -> ()  (* Silently drop *)
         | `Block -> (* Wait for space *)
         | `Raise -> raise Queue_overflow
       else
         Queue.push event t.queue
   end
   ```

2. **Create Batching Sink** (`lib/batching_sink.ml`):
   ```ocaml
   module Batching_sink : sig
     type t
     val create :
       ?max_batch_size:int ->
       ?max_delay_ms:int ->
       Sink.S -> t
   end = struct
     type t = {
       buffer: Log_event.t list ref;
       max_size: int;
       max_delay: float;
       inner: Sink.S;
       mutable timer: unit Lwt.t option;
     }
     
     let emit t event =
       t.buffer := event :: !(t.buffer);
       if List.length !(t.buffer) >= t.max_size then
         flush_batch t
   end
   ```

3. **Update Configuration API**:
   ```ocaml
   (* In configuration.ml *)
   val write_to_console_async : 
     ?max_queue_size:int ->
     ?colors:bool -> unit -> t -> t
   
   val write_to_file_async :
     ?max_queue_size:int ->
     ?rolling:File_sink.rolling_policy ->
     string -> t -> t
   
   val with_batching :
     ?max_batch_size:int ->
     ?max_delay_ms:int -> t -> t
   ```

4. **Integration with Logger**:
   - Modify Logger to optionally wrap sinks with async/batching
   - Ensure proper cleanup on shutdown
   - Handle exceptions in async workers

#### Dependencies
- Requires understanding of Eio (already a dependency)
- May need Lwt for async operations (or stick with Eio)

#### Success Criteria
- [ ] Async sink wrapper implemented
- [ ] Batching sink with configurable policies
- [ ] Non-blocking emit operations
- [ ] Proper flush/close lifecycle
- [ ] Memory-efficient under high load
- [ ] Backpressure handling configurable
- [ ] Tests for async behavior and edge cases

---

### 2.2 Optimize JSON Generation

**Priority**: Medium
**Effort**: 1 week
**Files**: `lib/log_event.ml`, `lib/json_sink.ml`

#### Current Implementation Analysis
Current JSON generation builds `Yojson.Safe.t` structures then serializes:
```ocaml
(* Current - allocates intermediate structure *)
let to_yojson event =
  `Assoc [
    ("@t", `String timestamp);
    ("@mt", `String event.message_template);
    ...
  ]
```

#### Proposed Optimizations

1. **Direct string building** for hot path:
   ```ocaml
   (* New - build string directly with Buffer *)
   let to_json_string event buf =
     Buffer.add_string buf "{@t:\"";
     Buffer.add_string buf (Ptime.to_rfc3339 event.timestamp);
     Buffer.add_string buf "\",@mt:\"";
     Buffer.add_string buf (escape_json event.message_template);
     ...
   ```

2. **Property serialization optimization**:
   ```ocaml
   let json_of_property buf (key, value) =
     Buffer.add_char buf '"';
     Buffer.add_string buf key;
     Buffer.add_string buf "\":";
     append_json_value buf value
   ```

3. **Escape JSON strings efficiently**:
   ```ocaml
   let escape_json s =
     let buf = Buffer.create (String.length s + 10) in
     String.iter (function
       | '"' -> Buffer.add_string buf "\\\""
       | '\\' -> Buffer.add_string buf "\\\\"
       | '\n' -> Buffer.add_string buf "\\n"
       | c -> Buffer.add_char buf c
     ) s;
     Buffer.contents buf
   ```

#### Success Criteria
- [ ] Benchmark shows 20%+ improvement in JSON generation
- [ ] Memory allocation reduced
- [ ] All existing tests pass
- [ ] JSON output format unchanged

---

### 2.3 Optimize String Rendering

**Priority**: Medium
**Effort**: 3-4 days
**Files**: `ppx/code_generator.ml`, `lib/runtime_helpers.ml`

#### Current Implementation
Uses `Printf.sprintf` for string rendering:
```ocaml
(* Current - PPX generates *)
Printf.sprintf "User %s logged in from %s" name ip_address
```

#### Proposed Optimizations

1. **Use `Buffer` for complex templates**:
   ```ocaml
   (* For templates with many parts *)
   let buf = Buffer.create 256 in
   Buffer.add_string buf "User ";
   Buffer.add_string buf name;
   Buffer.add_string buf " logged in from ";
   Buffer.add_string buf ip_address;
   Buffer.contents buf
   ```

2. **Optimize simple templates** (single variable):
   ```ocaml
   (* Simple concatenation for simple cases *)
   "User " ^ name ^ " logged in from " ^ ip_address
   ```

3. **PPX generates optimal code** based on template complexity:
   ```ocaml
   (* PPX logic *)
   if List.length parts <= 2 then
     generate_concatenation ~loc parts
   else if has_format_specifiers parts then
     generate_printf ~loc parts
   else
     generate_buffer ~loc parts
   ```

#### Success Criteria
- [ ] Benchmark improvement for complex templates
- [ ] Simple templates use fastest method
- [ ] No regression in simple cases
- [ ] Code remains readable

---

### 2.4 Add Comprehensive Benchmarks

**Priority**: Medium
**Effort**: 3-4 days
**Files**: `benchmarks/benchmark.ml` (extend)

#### Benchmarks to Add

1. **Sink I/O Performance**:
   ```ocaml
   (* Test file sink throughput *)
   let bench_file_sink () =
     let logger = (* setup file sink *) in
     time_it 100_000 (fun () ->
       Logger.information logger "Test message" []
     )
   
   (* Test console sink *)
   let bench_console_sink () =
     (* Similar setup *)
   
   (* Test composite sink *)
   let bench_composite_sink () =
     (* Multiple sinks *)
   ```

2. **Context Operations**:
   ```ocaml
   let bench_context_push_pop () =
     time_it 1_000_000 (fun () ->
       Log_context.with_property "key" (`String "value") (fun () -> ())
     )
   
   let bench_context_merge () =
     (* Test property merging cost *)
   ```

3. **Filter Performance**:
   ```ocaml
   let bench_level_filter () =
     (* Test level checking speed *)
   
   let bench_property_filter () =
     (* Test property matching cost *)
   ```

4. **Memory Allocation**:
   ```ocaml
   let bench_memory_usage () =
     (* Use Gc.stat to measure allocations *)
   ```

5. **Comparison with Other Libraries**:
   ```ocaml
   let bench_vs_logs () =
     (* Compare with 'logs' library *)
   
   let bench_vs_dolog () =
     (* Compare with 'dolog' library *)
   ```

#### Success Criteria
- [ ] Benchmark suite covers all major operations
- [ ] Comparison with other OCaml logging libraries
- [ ] Memory allocation profiling
- [ ] Automated benchmark runs in CI
- [ ] Performance regression detection

---

## Phase 3: Features & Enhancements

### 3.1 Improve PPX Error Messages

**Priority**: Medium
**Effort**: 1 week
**Files**: `ppx/ppx_message_templates.ml`, `ppx/scope_analyzer.ml`

#### Current Error Messages
```
MessageTemplates: Parse error: Failed to parse template
```

#### Improved Error Messages

1. **Template parse errors with context**:
   ```
   Error: Invalid template syntax at position 12
   
   Template: "Hello {user name}"
                     ^
   
   Hole names can only contain alphanumeric characters and underscores.
   Did you mean: "Hello {user_name}"?
   ```

2. **Variable not found errors**:
   ```
   Error: Variable 'username' not found in scope
   
   Template: "User {username} logged in"
                  ^^^^^^^^
   
   Available variables in scope:
   - user : string
   - ip_address : string
   - timestamp : float
   
   Did you mean: 'user'?
   ```

3. **Type mismatch hints** (if type info available):
   ```
   Warning: Variable 'count' has type int but format specifier ':s' expects string
   ```

#### Implementation Steps

1. **Enhance parser to track positions**:
   ```ocaml
   type parse_error = {
     position: int;
     message: string;
     suggestion: string option;
   }
   ```

2. **Update scope analyzer for better error context**:
   ```ocaml
   let raise_variable_not_found ~loc name scope =
     let available = list_available_variables scope in
     let suggestion = find_similar_name name available in
     Location.raise_errorf ~loc
       "Variable '%s' not found in scope@.\
       Available: %a@.\
       Did you mean: '%s'?"
       name
       (Fmt.list Fmt.string) available
       suggestion
   ```

3. **Add quick fixes** where possible

#### Success Criteria
- [ ] Error messages include position in template
- [ ] Suggestions for common mistakes
- [ ] List of available variables on scope errors
- [ ] Format specifier mismatch warnings

---

### 3.2 Add Log Correlation ID Support

**Priority**: Medium
**Effort**: 3-4 days
**Files**: `lib/log_context.ml`, `lib/log_event.ml`

#### Implementation Plan

1. **Built-in correlation ID context**:
   ```ocaml
   (* In log_context.ml *)
   val with_correlation_id : string -> (unit -> 'a) -> 'a
   val get_correlation_id : unit -> string option
   
   (* Auto-generate if not provided *)
   val with_correlation_id_auto : (unit -> 'a) -> 'a
   ```

2. **Automatic inclusion in log events**:
   ```ocaml
   (* In log_event.ml *)
   type t = {
     ...
     correlation_id: string option;  (* New field *)
   }
   
   let to_yojson event =
     `Assoc ([...] @ 
       match event.correlation_id with
       | Some id -> [("CorrelationId", `String id)]
       | None -> [])
   ```

3. **PPX support for correlation IDs**:
   ```ocaml
   [%log.information ~correlation_id:req_id "Processing request"]
   ```

4. **Configuration for distributed tracing**:
   ```ocaml
   Configuration.create ()
   |> Configuration.with_correlation_id_header "X-Request-ID"
   |> Configuration.with_correlation_id_generator generate_uuid
   ```

#### Success Criteria
- [ ] Correlation ID flows through context
- [ ] Automatic inclusion in all log events
- [ ] PPX supports explicit correlation ID
- [ ] Configuration for integration with web frameworks
- [ ] Tests for correlation ID propagation

---

### 3.3 Add PII/Sensitive Data Redaction

**Priority**: Medium
**Effort**: 1 week
**Files**: New `lib/redaction.ml`, modifications to PPX and logger

#### Implementation Plan

1. **Redaction configuration**:
   ```ocaml
   (* lib/redaction.ml *)
   type t = 
   | Redact_all  (* Replace with "***" *)
   | Redact_partial of {show_first: int; show_last: int}
   | Hash of [ `Md5 | `Sha256 ]
   | Custom of (string -> string)
   
   val redact : t -> string -> string
   ```

2. **Template-level redaction**:
   ```ocaml
   (* Syntax: {#var} for redacted *)
   let msg, json = [%template "User: {username}, SSN: {#ssn}"] in
   (* Output: User: alice, SSN: *** *)
   ```

3. **Global redaction rules**:
   ```ocaml
   Configuration.create ()
   |> Configuration.redact_fields_matching ~pattern:"[Pp]assword"
   |> Configuration.redact_fields_matching ~pattern:"[Ss]ecret"
   |> Configuration.redact_fields ["ssn"; "credit_card"]
   ```

4. **Automatic redaction by type**:
   ```ocaml
   (* If type info available *)
   type user = {
     name: string;
     [@redact Partial {show_first=3; show_last=0}]
     ssn: string;
   }
   ```

#### Success Criteria
- [ ] Redaction operators in templates
- [ ] Global redaction rules by field name
- [ ] Multiple redaction strategies
- [ ] Performance overhead minimal
- [ ] Tests for all redaction modes

---

### 3.4 Add Request Middleware Helper

**Priority**: Low
**Effort**: 2-3 days
**Files**: New `lib/request_context.ml`

#### Implementation

1. **Request logging middleware**:
   ```ocaml
   module Request_context : sig
     type t = {
       request_id: string;
       start_time: Mtime.t;
       user_agent: string option;
       client_ip: string option;
     }
     
     val with_request : (t -> 'a) -> 'a
     val log_request_start : unit -> unit
     val log_request_end : ?status:int -> unit -> unit
     val get_duration_ms : unit -> float
   end
   ```

2. **Integration example for web frameworks**:
   ```ocaml
   (* Dream integration example *)
   let log_middleware handler req =
     Request_context.with_request (fun ctx ->
       log_request_start ();
       let%lwt response = handler req in
       log_request_end ~status:(Dream.status response);
       Lwt.return response
     )
   ```

#### Success Criteria
- [ ] Request context module
- [ ] Automatic duration tracking
- [ ] Integration examples for common frameworks
- [ ] Tests for request lifecycle

---

### 3.5 Unify Template Parser Logic

**Priority**: Low
**Effort**: 3-4 days
**Files**: Refactor between `lib/template_parser.ml` and `ppx/`

#### Current State
Parser logic exists in two places:
- `lib/template_parser.ml` - Runtime parser
- `ppx/template_parser.ml` - Compile-time parser (likely)

#### Proposed Solution

1. **Create shared parser module**:
   ```ocaml
   (* lib/template_parser_intf.ml *)
   module type S = sig
     type parsed_template
     val parse : string -> (parsed_template, string) result
   end
   
   (* Shared implementation *)
   module Make_parser(Types : Template_types.S) : S
   ```

2. **Use functors to share code**:
   ```ocaml
   (* lib/template_parser.ml *)
   module Parser = Make_parser(Types)
   
   (* ppx/template_parser.ml *)
   module Parser = Make_parser(Ppx_types)
   ```

3. **Benefits**:
   - Single source of truth for parsing logic
   - Consistent behavior between runtime and compile-time
   - Easier maintenance

#### Success Criteria
- [ ] Parser logic unified in single location
- [ ] Both runtime and PPX use shared code
- [ ] All tests pass
- [ ] No behavioral changes

---

## Phase 4: Documentation & Polish

### 4.1 Generate API Documentation

**Priority**: High
**Effort**: 2-3 days
**Files**: Documentation comments in all `.mli` files

#### Tasks

1. **Ensure all public modules have .mli files**:
   - Check `lib/` for modules without interfaces
   - Create missing `.mli` files

2. **Add comprehensive odoc comments**:
   ```ocaml
   (** {2 Log Levels}
       
       Six standard log levels ordered by severity:
       - Verbose: Detailed diagnostic information
       - Debug: Information useful for debugging
       - Information: General application flow
       - Warning: Potentially harmful situations
       - Error: Error events that might still allow continuation
       - Fatal: Severe errors that cause termination
   *)
   ```

3. **Generate and publish docs**:
   ```bash
   dune build @doc
   # Host on GitHub Pages or ocaml.org
   ```

#### Success Criteria
- [ ] All public APIs documented
- [ ] odoc generates without warnings
- [ ] Docs hosted and accessible
- [ ] Examples included in documentation

---

### 4.2 Create Migration Guide

**Priority**: Medium
**Effort**: 2-3 days
**Files**: `MIGRATION.md`

#### Content Outline

1. **From `logs` library**:
   - Mapping log levels
   - Converting reporters to sinks
   - Migrating from tags to properties

2. **From `dolog` library**:
   - Level mapping
   - Output redirection
   - Configuration differences

3. **From Printf-style logging**:
   - Converting format strings to templates
   - Adding structured output
   - Best practices

4. **Common patterns**:
   - Before/after code examples
   - Feature comparison table

#### Success Criteria
- [ ] Migration guide for each common logging library
- [ ] Code examples for common patterns
- [ ] Feature comparison table
- [ ] Troubleshooting section

---

### 4.3 Create Production Deployment Guide

**Priority**: Medium
**Effort**: 2-3 days
**Files**: `DEPLOYMENT.md`

#### Content Outline

1. **Performance Tuning**:
   - Choosing sync vs async sinks
   - Batching configuration
   - Buffer sizes
   - File rolling strategies

2. **Monitoring & Health Checks**:
   - Sink health monitoring
   - Queue depth alerts
   - Log volume metrics

3. **Resource Management**:
   - File descriptor limits
   - Disk space management
   - Memory usage patterns

4. **Security Considerations**:
   - PII redaction setup
   - Log file permissions
   - Sensitive data handling

5. **Troubleshooting**:
   - Common issues
   - Debug mode
   - Performance diagnostics

#### Success Criteria
- [ ] Production checklist
- [ ] Performance tuning guidelines
- [ ] Security best practices
- [ ] Troubleshooting guide

---

## Implementation Schedule

### Suggested Timeline

**Weeks 1-3: Phase 1 - Critical Safety & Testing**
- Week 1: Json_sink tests, Obj module replacement (start)
- Week 2: Parser error tests, alignment tests
- Week 3: Complete Obj module replacement, test_escape conversion

**Weeks 4-7: Phase 2 - Performance & Architecture**
- Week 4: Async/batching sink design
- Week 5: Async/batching implementation
- Week 6: JSON generation optimization
- Week 7: String rendering optimization, benchmarks

**Weeks 8-13: Phase 3 - Features & Enhancements**
- Week 8: PPX error message improvements
- Week 9: Correlation ID support
- Week 10: PII redaction
- Week 11: Request middleware
- Week 12-13: Template parser unification

**Weeks 14-15: Phase 4 - Documentation & Polish**
- Week 14: API documentation, migration guide
- Week 15: Deployment guide, final polish

### Parallel Development Opportunities

Two developers can work in parallel on:
- **Developer A**: Phase 1 (testing) + Phase 2 (async/batching)
- **Developer B**: Phase 2 (optimizations) + Phase 3 (features)

This reduces timeline to **6-8 weeks** total.

---

## Testing Strategy

### Test Coverage Goals

| Module | Current | Target |
|--------|---------|--------|
| Json_sink | 0% | 95%+ |
| Template_parser | 60% | 90%+ |
| Runtime_helpers | 40% | 80%+ |
| Async/batching | N/A | 90%+ |
| Overall | 70% | 85%+ |

### Test Categories

1. **Unit tests**: Individual module testing
2. **Integration tests**: End-to-end logging scenarios
3. **Property tests**: Using QCheck for generative testing
4. **Performance tests**: Benchmark regression detection
5. **Stress tests**: High-volume logging scenarios

### CI Integration

```yaml
# .github/workflows/test.yml
- Run all tests
- Generate coverage report
- Run benchmarks (store results)
- Compare with baseline
- Fail on coverage regression >5%
- Fail on performance regression >10%
```

---

## Success Metrics

### Quantitative
- [ ] 85%+ test coverage
- [ ] 50%+ performance improvement in hot paths
- [ ] Zero `Obj` module usage
- [ ] <5% overhead compared to Printf for simple cases
- [ ] 10,000+ events/second throughput (file sink)

### Qualitative
- [ ] Error messages rated "helpful" by users
- [ ] Migration from other libraries takes <30 minutes
- [ ] Production deployment guide followed without issues
- [ ] Users report "easy to debug" issues

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Obj module replacement breaks compatibility | High | Gradual migration, backward compatibility layer |
| Async/batching adds complexity | Medium | Thorough testing, opt-in only |
| Performance optimizations break correctness | High | Comprehensive benchmarks, property tests |
| Timeline slips due to complexity | Medium | Parallel development, cut scope if needed |
| Dependencies become outdated | Low | Regular dependency updates, lock file |

---

## Conclusion

This improvement plan addresses critical gaps in testing, eliminates unsafe code patterns, and adds production-ready features like async I/O and PII redaction. The phased approach allows incremental delivery of value while managing risk.

**Recommended Starting Point**: Begin with Phase 1.1 (Json_sink tests) and Phase 1.2 (Obj module replacement) as these address the most critical gaps.

**Estimated Timeline**: 11-15 weeks for one developer, or 6-8 weeks for two developers working in parallel.

---

## Appendix: Task Checklist

### Phase 1
- [ ] 1.1 Add Json_sink tests
- [ ] 1.2 Replace Obj module usage
- [ ] 1.3 Add parser error tests
- [ ] 1.4 Add alignment tests
- [ ] 1.5 Convert test_escape.ml

### Phase 2
- [ ] 2.1 Implement async/batching sinks
- [ ] 2.2 Optimize JSON generation
- [ ] 2.3 Optimize string rendering
- [ ] 2.4 Add comprehensive benchmarks

### Phase 3
- [ ] 3.1 Improve PPX error messages
- [ ] 3.2 Add correlation ID support
- [ ] 3.3 Add PII redaction
- [ ] 3.4 Add request middleware
- [ ] 3.5 Unify template parser

### Phase 4
- [ ] 4.1 Generate API documentation
- [ ] 4.2 Create migration guide
- [ ] 4.3 Create deployment guide

---

**Last Updated**: 2026-01-31
**Document Version**: 1.0
