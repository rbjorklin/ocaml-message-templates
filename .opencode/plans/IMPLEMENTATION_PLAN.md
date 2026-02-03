# OCaml Message Templates: Implementation Plan

## Executive Summary

This document outlines the implementation of **ocaml-message-templates**, a PPX-based library for Message Templates in OCaml 5.4.0 that provides compile-time template validation with automatic variable capture from scope, leveraging the new effects system through Eio.

**Key Design Decisions:**
- **OCaml 5.4.0**: Leverages the latest release with improved performance and features
- **Pattern 2 (Auto-capture)**: Variables referenced in templates are automatically captured from lexical scope
- **Hard compile-time errors**: Undefined variables cause compilation failures
- **Yojson integration**: Native support for JSON/structured output
- **Eio integration**: Effects-based concurrency for high-performance logging
- **PPX-driven**: Full compile-time parsing and code generation

### Why OCaml 5.4.0 and Eio?

**OCaml 5.4.0** brings significant improvements that make it ideal for high-performance structured logging:

1. **Native Multicore Support**: Unlike previous versions that relied on a global runtime lock, OCaml 5.4.0 allows true parallel execution of logging operations across multiple CPU cores, dramatically improving throughput for high-volume applications.

2. **Effects System**: The built-in effects system enables lightweight concurrency without the overhead of traditional threads, perfect for handling thousands of concurrent log operations.

3. **Improved Runtime Performance**: Better garbage collection and memory management specifically benefit high-throughput logging scenarios where millions of log events are processed.

**Eio** (Effects-based I/O) is the modern standard for concurrent programming in OCaml 5.x:

- **Structured Concurrency**: Automatically manages resource lifetimes, preventing resource leaks in logging pipelines
- **Zero-Copy I/O**: Efficient handling of log data without unnecessary memory copies
- **Composable Effects**: Clean integration with other effect-based libraries
- **Cancelation Support**: Safe handling of timeout and cancellation in logging operations
- **Cross-Platform**: Works on Linux, macOS, Windows, and even in browsers via js_of_ocaml

Traditional solutions like Lwt and Async rely on monadic concurrency, which requires explicit async/await syntax and callback chains. Eio's effect handlers provide a more natural, direct-style programming model while maintaining composability and performance.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Source Code with [%template "..."]                          │
└────────────────────┬────────────────────────────────────────┘
                     │ PPX Rewriter
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  1. Template Parser (Angstrom)                              │
│     • Extract holes: {var}, {@obj}, {$str}                  │
│     • Validate syntax against Message Templates spec        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  2. Scope Analyzer (PPX Context)                            │
│     • Query current environment for variable existence      │
│     • Type-check variables against template usage           │
│     • Hard error on undefined variables                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Code Generator (AST Builder)                            │
│     • Generate string rendering function                    │
│     • Generate Yojson structure for structured logging      │
│     • Inline optimized output                               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Compiled OCaml 5.4.0 Code                                  │
│  (Zero runtime parsing overhead)                            │
└─────────────────────────────────────────────────────────────┘
```

**OCaml 5.4.0 Benefits:**
- Native support for multicore parallelism
- Improved runtime performance for generated code
- Better memory management for high-throughput logging
- Foundation for Eio integration

---

## 2. Core Components

### 2.1 Template Parser (Angstrom)

**Grammar Implementation:**

```ocaml
type hole = {
  name: string;
  operator: [ `Default | `Structure | `Stringify ];
  format: string option;
  alignment: (bool * int) option;  (* (is_negative, width) *)
}

type template_part =
  | Text of string
  | Hole of hole

type parsed_template = template_part list
```

**Parsing Rules:**

| Pattern | Meaning | Example |
|---------|---------|---------|
| `{name}` | Default capture | `{username}` |
| `{@name}` | Structure preservation | `{@user}` → Yojson JSON object |
| `{$name}` | Stringification | `{$value}` → `string_of_int` etc. |
| `{name:000}` | Format specifier | `{count:000}` → zero-padded |
| `{name,-10}` | Left alignment | `{name,-10}` |
| `{name,10}` | Right alignment | `{name,10}` |
| `{{` | Escaped `{` | `{{not_a_hole}}` |

**Parser Implementation:**

```ocaml
open Angstrom

let hole_name = take_while1 (function
  | '0'..'9' | 'a'..'z' | 'A'..'Z' | '_' -> true
  | _ -> false)

let operator = option `Default (char '@' *> return `Structure <|>
                                 char '$' *> return `Stringify)

let format_spec = char ':' *> take_while1 (fun c -> c <> '}')

let alignment = char ',' *>
  option false (char '-' *> return true) >>= fun neg ->
  take_while1 (function '0'..'9' -> true | _ -> false) >>| fun n ->
  (neg, int_of_string n)

let hole =
  char '{' *>
  operator >>= fun op ->
  hole_name >>= fun name ->
  option None (alignment >>| fun a -> Some a) >>= fun align ->
  option None (format_spec >>| fun f -> Some f) >>= fun fmt ->
  char '}' *> return (Hole { name; operator = op; format = fmt; alignment = align })

let escaped_brace = string "{{" *> return (Text "{") <|>
                    string "}}" *> return (Text "}")

let text = take_while1 (fun c -> c <> '{') >>| fun s -> Text s

let template = many (text <|> escaped_brace <|> hole)
```

### 2.2 Scope Analyzer (PPXlib)

**Challenge**: PPX operates on AST before type-checking, but we need to know if variables exist.

**Solution**: Use PPXlib's expansion context and AST traversal.

```ocaml
open Ppxlib
open Ast_builder.Default

(* Context tracking current bindings *)
type scope = {
  bindings: (string * core_type option) list;
  outer_scopes: scope list;
}

(* Check if variable exists in scope chain *)
let rec find_variable scope var_name =
  match List.assoc_opt var_name scope.bindings with
  | Some ty -> Some ty
  | None ->
      match scope.outer_scopes with
      | [] -> None
      | outer :: rest -> find_variable { scope with bindings = outer.bindings; outer_scopes = rest } var_name

(* Hard error on undefined variable *)
let validate_variable ~loc scope var_name =
  match find_variable scope var_name with
  | None ->
      Location.raise_errorf ~loc
        "MessageTemplates: Variable '%s' not found in scope. " ^^
        "Ensure the variable is defined before using it in a template."
        var_name
  | Some ty -> ty
```

**Scope Tracking Strategy:**

The PPX tracks bindings through AST nodes:

```ocaml
let rec analyze_scope ast =
  match ast with
  | { pexp_desc = Pexp_let (_, vbs, body); _ } ->
      let new_bindings = List.map (fun vb ->
        (Pat.to_string vb.pvb_pat, vb.pvb_expr.pexp_type)
      ) vbs in
      analyze_scope body
  | { pexp_desc = Pexp_fun (_, _, pat, body); _ } ->
      (* Extract parameter names from pattern *)
      let params = extract_pattern_names pat in
      analyze_scope body
  | { pexp_desc = Pexp_match (_, cases); _ } ->
      List.iter analyze_case cases
  | { pexp_desc = Pexp_try (_, cases); _ } ->
      List.iter analyze_case cases
  | _ -> ()
```

### 2.3 Code Generator

**Generated Code Structure:**

For a template `"User {username} logged in from {ip_address}"`:

```ocaml
(* Generated code *)
let __template_result =
  let __string_render =
    Printf.sprintf "User %s logged in from %s" username ip_address
  in
  let __structured_render =
    `Assoc [
      ("template", `String "User {username} logged in from {ip_address}");
      ("username", `String username);
      ("ip_address", `String ip_address);
    ]
  in
  (__string_render, __structured_render)
```

**Type-Specific Conversion to Yojson:**

```ocaml
let yojson_of_value ~loc (expr : expression) (ty : core_type option) =
  match ty with
  | Some [%type: string] -> [%expr `String [%e expr]]
  | Some [%type: int] -> [%expr `Int [%e expr]]
  | Some [%type: float] -> [%expr `Float [%e expr]]
  | Some [%type: bool] -> [%expr `Bool [%e expr]]
  | Some [%type: int64] -> [%expr `Intlit (Int64.to_string [%e expr])]
  | Some [%type: Yojson.Safe.t] -> expr  (* Already JSON *)
  | _ ->
      (* Fallback: convert to string *)
      [%expr `String (Format.asprintf "%a" pp [%e expr])]
```

**Operator Handling:**

```ocaml
let apply_operator ~loc op expr ty =
  match op with
  | `Default -> yojson_of_value ~loc expr ty
  | `Structure ->
      (* Assume value is already Yojson.Safe.t or can be converted *)
      [%expr
        match [%e expr] with
        | #Yojson.Safe.t as json -> json
        | v -> `String (Yojson.Safe.to_string v)
      ]
  | `Stringify ->
      [%expr `String (string_of_value [%e expr])]
```

---

## 3. PPX Implementation

### 3.1 Main Extension Point

```ocaml
open Ppxlib

let name = "template"

let expand ~ctxt template_str =
  let loc = Expansion_context.Extension.extension_point_loc ctxt in
  let scope = Expansion_context.Extension.bindings ctxt in

  (* 1. Parse the template *)
  let parsed = match Angstrom.parse_string ~consume:All template_parser template_str with
    | Ok parts -> parts
    | Error msg -> Location.raise_errorf ~loc "MessageTemplates: Parse error: %s" msg
  in

  (* 2. Extract hole names and validate scope *)
  let holes = extract_holes parsed in
  List.iter (fun hole ->
    ignore (validate_variable ~loc scope hole.name)
  ) holes;

  (* 3. Generate code *)
  generate_template_code ~loc scope parsed

let extension =
  Extension.V3.declare
    name
    Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    expand

let rule = Ppxlib.Context_free.Rule.extension extension
let () = Driver.register_transformation ~rules:[rule] "message-templates"
```

### 3.2 Code Generation Details

```ocaml
let generate_template_code ~loc scope parts =
  (* Build format string for Printf *)
  let fmt_string = build_format_string parts in

  (* Collect variable expressions *)
  let var_exprs = List.filter_map (function
    | Text _ -> None
    | Hole h ->
        let var = evar ~loc h.name in
        Some (apply_format ~loc h var)
  ) parts in

  (* Build string render *)
  let string_render =
    eapply ~loc (evar ~loc "Printf.sprintf")
      (estring ~loc fmt_string :: var_exprs)
  in

  (* Build structured render *)
  let properties = List.filter_map (function
    | Text _ -> None
    | Hole h ->
        let ty = find_variable scope h.name in
        let value_expr = apply_operator ~loc h.operator (evar ~loc h.name) ty in
        Some (h.name, value_expr)
  ) parts in

  let template_field = ("template", estring ~loc (reconstruct_template parts)) in
  let assoc_fields = template_field :: properties in
  let json_expr = make_yojson_assoc ~loc assoc_fields in

  (* Return tuple: (string, Yojson.Safe.t) *)
  pexp_tuple ~loc [string_render; json_expr]
```

---

## 4. Dependencies

### 4.1 Build Dependencies

```dune
(depends
  (ocaml (>= 5.4.0))
  (ppxlib (>= 0.35.0))
  (angstrom (>= 0.15.0))
  (yojson (>= 2.0.0))
  (eio (>= 1.0)))
```

### 4.2 Runtime Dependencies

Yojson for structured output and Eio for effects-based concurrency:

```dune
(libraries yojson eio)
```

---

## 5. API Design

### 5.1 Basic Usage

```ocaml
open Message_templates

let () =
  let username = "alice" in
  let ip_address = "192.168.1.1" in

  (* Pattern 2: Auto-capture from scope *)
  let msg, json = [%template "User {username} logged in from {ip_address}"] in

  Printf.printf "%s\n" msg;
  (* Output: User alice logged in from 192.168.1.1 *)

  Yojson.Safe.to_string json |> print_endline;
  (* Output: {"template":"User {username} logged in from {ip_address}",
             "username":"alice",
             "ip_address":"192.168.1.1"} *)
```

### 5.2 With Operators

```ocaml
let () =
  let user = { id = 42; name = "Alice"; email = "alice@example.com" } in
  let count = 7 in

  (* Structure operator: serialize object *)
  let msg, json = [%template "User {@user} made {count} requests"] in

  (* json will be:
     {"template":"User {@user} made {count} requests",
      "user":{"id":42,"name":"Alice","email":"alice@example.com"},
      "count":7}
  *)
```

### 5.3 Format Specifiers

```ocaml
let () =
  let count = 42 in
  let amount = 1234.56 in

  (* Zero-padded integers *)
  let msg, _ = [%template "ID: {count:00000}"] in
  (* Output: ID: 00042 *)

  (* Float formatting *)
  let msg, _ = [%template "Amount: ${amount:.2f}"] in
  (* Output: Amount: $1234.56 *)
```

### 5.4 Compile-Time Errors

```ocaml
let () =
  let username = "alice" in
  (* ip_address NOT defined *)

  [%template "User {username} logged in from {ip_address}"]
  (* Compile error:
     MessageTemplates: Variable 'ip_address' not found in scope.
     Ensure the variable is defined before using it in a template.
  *)
```

---

## 6. Implementation Phases

### Phase 1: Core Infrastructure (Week 1-2)

**Goals:**
- Set up project structure with dune
- Implement template parser with Angstrom
- Basic PPX registration

**Tasks:**
1. Create `lib/` and `ppx/` directories
2. Implement `Template_parser` module with full grammar
3. Write comprehensive parser tests
4. Set up PPX scaffolding with ppxlib

**Deliverable:** Parser that can extract holes from templates

### Phase 2: Scope Analysis (Week 3-4)

**Goals:**
- Implement scope tracking in PPX
- Variable validation with hard errors
- Type information extraction

**Tasks:**
1. Research PPXlib's binding extraction APIs
2. Implement `Scope_analyzer` module
3. Create test cases for scope detection
4. Error message refinement

**Deliverable:** PPX that validates variable existence at compile time

### Phase 3: Code Generation (Week 5-6)

**Goals:**
- String rendering with Printf
- Yojson structured output
- Operator support (@, $)

**Tasks:**
1. Implement `Code_generator` module
2. Format string building from templates
3. Type-specific Yojson converters
4. Escape sequence handling

**Deliverable:** Working code generation for string and JSON output

### Phase 4: Advanced Features (Week 7-8)

**Goals:**
- Format specifiers (:format)
- Alignment specifiers (,width)
- Edge case handling

**Tasks:**
1. Implement format specifier parsing
2. Add alignment support
3. Handle special characters and escaping
4. Deeply nested structures with @ operator

**Deliverable:** Full Message Templates specification compliance

### Phase 5: Testing & Documentation (Week 9-10)

**Goals:**
- Comprehensive test suite
- Documentation and examples
- Performance benchmarks

**Tasks:**
1. Unit tests for all parser edge cases
2. Integration tests with real OCaml code
3. PPX expectation tests
4. Documentation and usage guide
5. Benchmark vs runtime parsing approaches

**Deliverable:** Production-ready library with documentation

---

## 7. Comparison with Serilog/Seq-Style Implementations

### 7.1 Runtime Parsing (Serilog C#)

**C# Example:**
```csharp
var username = "alice";
var ipAddress = "192.168.1.1";

// Runtime parsing happens every time
Log.Information("User {username} logged in from {ip_address}", username, ipAddress);

// Serilog stores:
// - Template: "User {username} logged in from {ip_address}"
// - Properties: { username: "alice", ip_address: "192.168.1.1" }
```

**Characteristics:**
- Template parsed at **runtime**
- No compile-time validation of property names
- Performance overhead per log call
- Flexible: can log with different templates dynamically

### 7.2 PPX-Based (OCaml Proposed)

**OCaml Example:**
```ocaml
let username = "alice" in
let ip_address = "192.168.1.1" in

(* Compile-time processing *)
let msg, json = [%template "User {username} logged in from {ip_address}"]

(* Generated at compile time:
   let msg = Printf.sprintf "User %s logged in from %s" username ip_address
   let json = `Assoc [
     ("template", `String "User {username} logged in from {ip_address}");
     ("username", `String username);
     ("ip_address", `String ip_address)
   ]
*)
```

**Characteristics:**
- Template parsed at **compile time**
- Hard errors for missing variables
- Zero runtime parsing overhead
- Inlined optimal code
- **Eio integration**: Effects-based concurrency for fiber-based logging
- **OCaml 5.4.0**: Modern multicore runtime for parallel log processing

### 7.3 Feature Comparison Matrix

| Feature | Serilog (C#) | Proposed OCaml | Notes |
|---------|--------------|----------------|-------|
| **Compile-time validation** | ❌ | ✅ | OCaml catches typos at build |
| **Runtime performance** | Moderate | Excellent | OCaml has zero parsing cost |
| **Dynamic templates** | ✅ | ❌ | OCaml requires static strings |
| **Type safety** | Limited | Full | OCaml integrates with type system |
| **Structured output** | ✅ | ✅ | Both support JSON/property bags |
| **Scopes/contexts** | Enrichers | Lexical scope | Different approaches to context |
| **Filtering/routing** | Log level + sinks | Type-driven | OCaml can use types for routing |
| **Template reuse** | Named templates | Let-bindings | OCaml uses functions |
| **Concurrency model** | Async/Task | **Eio effects** | OCaml 5.4.0 uses lightweight fibers |
| **Multicore support** | Thread-pool | **Native parallelism** | OCaml 5.4.0 has true multicore |

### 7.4 Architecture Differences

**Serilog Pipeline:**
```
Log Statement → Parse Template → Match Args → Create LogEvent →
Enrich → Filter → Format → Output
```

**OCaml Pipeline (Compile-time):**
```
PPX Phase: Parse Template → Validate Scope → Generate Code

Runtime: Log Statement → Execute Generated Code → Output
```

### 7.5 When to Use Which

**Choose Serilog-style when:**
- Templates need to be dynamic/configurable at runtime
- Logging framework handles complex enrichment pipelines
- Integration with existing .NET ecosystem
- Developers prefer runtime flexibility over compile-time safety

**Choose OCaml PPX when:**
- Maximum performance is critical (zero runtime overhead)
- Compile-time guarantees prevent production bugs
- Static analysis and type safety are priorities
- Template structure is known at compile time
- Building embedded/high-performance systems

### 7.6 Hybrid Approaches

**Future Enhancement:** Support runtime templates with opt-in syntax:

```ocaml
(* Compile-time - default *)
[%template "User {username} logged in"]

(* Runtime - explicit *)
[%template.runtime config.log_template]
```

This would provide best of both worlds: type-safe by default, dynamic when needed.

---

## 8. Testing Strategy

### 8.1 Parser Tests

```ocaml
(* test/test_parser.ml *)
let test_cases = [
  ("simple", "Hello {name}",
   [Text "Hello "; Hole {name="name"; operator=`Default; format=None; alignment=None}]);
  ("with_format", "Count: {n:000}",
   [Text "Count: "; Hole {name="n"; operator=`Default; format=Some "000"; alignment=None}]);
  ("escaped", "{{not_a_hole}}",
   [Text "{not_a_hole}"]);
  (* ... more cases ... *)
]
```

### 8.2 PPX Expectation Tests

```ocaml
(* test/test_ppx.ml *)
let%expect_test "simple template" =
  let username = "alice" in
  let ip_address = "10.0.0.1" in
  [%template "User {username} from {ip_address}"]
  |> fun (s, j) ->
    print_endline s;
    Yojson.Safe.to_string j |> print_endline;
  [%expect {|
    User alice from 10.0.0.1
    {"template":"User {username} from {ip_address}","username":"alice","ip_address":"10.0.0.1"}
  |}]
```

### 8.3 Negative Tests (Compile Errors)

```ocaml
(* test/test_errors.ml *)
(* This file should fail to compile *)

let () =
  let x = 1 in
  [%template "Value: {y}"]  (* Error: y not in scope *)
```

### 8.4 Property-Based Tests

Using QCheck to verify round-trip properties:

```ocaml
let prop_parse_render =
  QCheck.Test.make ~count:1000
    ~name:"parse_render_roundtrip"
    template_generator
    (fun tmpl ->
      let parsed = parse tmpl in
      let rendered = render parsed in
      String.equal tmpl rendered)
```

---

## 9. Edge Cases & Error Handling

### 9.1 Syntax Errors

```ocaml
[%template "Hello {unclosed"]
(* Error: MessageTemplates: Parse error: unexpected end of input, expected '}' *)

[%template "Hello {invalid-name}"]
(* Error: MessageTemplates: Parse error: invalid character '-' in hole name *)
```

### 9.2 Scope Errors

```ocaml
let () =
  let x = 1 in
  [%template "{x} + {y}"]
  (* Error: MessageTemplates: Variable 'y' not found in scope *)
```

### 9.3 Type Errors

```ocaml
let () =
  let x = 42 in
  (* Using @ operator on non-serializable type *)
  [%template "Value: {@x}"]
  (* Warning: @ operator used on type int, will convert to string *)
```

### 9.4 Empty Templates

```ocaml
[%template ""]
(* Valid: returns ("", `Assoc [("template", `String "")]) *)
```

### 9.5 Special Characters

```ocaml
let () =
  let msg = "Hello\nWorld" in
  [%template "Message: {msg}"]
  (* Properly escapes newlines in JSON output *)
```

---

## 10. Future Enhancements

### 10.1 Named Template Definitions

```ocaml
(* Define reusable template *)
[%template.def log_login "User {username} logged in from {ip}"]

(* Use later *)
let username = "alice" and ip = "10.0.0.1" in
log_login  (* Expands to the template code *)
```

### 10.2 Localization Support

```ocaml
(* Template with i18n keys *)
[%template.i18n "messages" "user.login" {username} {ip}]
```

### 10.3 Performance Metrics

```ocaml
(* Include timing information automatically *)
[%template.timed "Processed {count} items"]
(* Adds: "duration_ms": 42 to JSON output *)
```

### 10.4 Integration with Loggers

```ocaml
(* Direct logging integration *)
[%log.info "User {username} logged in"]
(* Combines template expansion with logging framework *)
```

### 10.5 Eio Integration for High-Performance Logging

```ocaml
(* Fiber-based concurrent logging with Eio *)
let log_concurrent ~sw ~stdout events =
  List.iter (fun event ->
    Fiber.fork ~sw (fun () ->
      let user = event.user in
      let action = event.action in
      let msg, json = [%template "{user.name} {action}"] in
      Flow.copy_string msg stdout;
      send_async json
    )
  ) events

(* Using Eio's structured concurrency for resource safety *)
let with_logging_env ~clock f =
  Switch.run (fun sw ->
    let stdout = Eio.Stdout in
    f ~sw ~stdout ~clock
  )
```

---

## 11. Conclusion

This implementation plan outlines a type-safe, high-performance Message Templates library for OCaml leveraging PPX for compile-time processing. The approach offers significant advantages over runtime-parsing alternatives:

1. **Zero Runtime Overhead**: All parsing and validation done at compile time
2. **Type Safety**: Hard compile errors for undefined variables
3. **OCaml Idioms**: Leverages the type system and lexical scoping
4. **Standards Compliant**: Implements the Message Templates specification

The phased approach allows for incremental development with clear milestones and deliverables. Starting with the core parser and progressively adding scope analysis and code generation ensures a solid foundation.

**OCaml 5.4.0 Benefits**:
- Effects-based concurrency with Eio for high-performance structured logging
- Multicore parallelism support for log processing pipelines
- Modern runtime with improved performance characteristics

**Estimated Total Effort**: 10 weeks for production-ready library
**Priority**: Scope validation and code generation are critical path items
**Risk**: PPX scope analysis complexity; mitigated by ppxlib's mature APIs

---

## Appendix A: File Structure

```
ocaml-message-templates/
├── dune-project
├── message-templates.opam
├── lib/
│   ├── dune
│   ├── messageTemplates.ml
│   ├── messageTemplates.mli
│   └── types.ml
├── ppx/
│   ├── dune
│   ├── ppx_message_templates.ml
│   ├── parser.ml
│   ├── scope_analyzer.ml
│   └── code_generator.ml
├── test/
│   ├── dune
│   ├── test_parser.ml
│   ├── test_ppx.ml
│   └── test_errors.ml
└── examples/
    ├── basic.ml
    └── structured_logging.ml
```

## Appendix B: Opam File

```opam
opam-version: "2.0"
name: "message-templates"
version: "0.1.0"
synopsis: "Type-safe Message Templates for OCaml with PPX"
description: """
A PPX-based implementation of Message Templates for OCaml that provides
type-safe, compile-time validated templates with automatic scope capture
and both string and JSON output.
"""
depends: [
  "ocaml" {>= "5.4.0"}
  "dune" {>= "3.0"}
  "ppxlib" {>= "0.35.0"}
  "angstrom" {>= "0.15.0"}
  "yojson" {>= "2.0.0"}
  "eio" {>= "1.0"}
  "alcotest" {with-test}
  "qcheck" {with-test}
]
build: [
  ["dune" "subst"] {dev}
  ["dune" "build" "-p" name "-j" jobs]
]
```

## Appendix C: Example dune File for PPX

```dune
(library
 (public_name message-templates.ppx)
 (name ppx_message_templates)
 (kind ppx_rewriter)
 (libraries
   ppxlib
   angstrom)
 (preprocess (pps ppxlib.metaquot)))
```

## Appendix D: Example Usage with Eio (Effects-Based Concurrency)

```ocaml
(* Integration with Eio effects-based concurrency *)
open Eio

let log_user_login ~stdout user_id =
  let user = fetch_user user_id in
  let ip = get_client_ip () in
  let msg, json = [%template "User {user.name} logged in from {ip}"] in
  Flow.copy_string msg stdout;
  send_to_log_aggregator json

(* Example with structured concurrency *)
let log_with_timeout ~clock ~stdout tmpl_vars =
  let timeout = Time.Timeout.seconds clock 5.0 in
  Time.Timeout.run_exn timeout (fun () ->
    let username = tmpl_vars.username in
    let action = tmpl_vars.action in
    let msg, json = [%template "User {username} performed {action}"] in
    Flow.copy_string msg stdout;
    json
  )
```

## Apendix E: References

* https://messagetemplates.org/
