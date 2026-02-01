# OCaml Message Templates

A PPX-based library for Message Templates in OCaml that provides compile-time template validation with automatic variable capture from scope.

## Features

- **Compile-time Validation**: Template syntax and variable existence checked at compile time
- **Type Safety**: Hard compile errors for undefined variables
- **Dual Output**: Generate both formatted strings and structured JSON output
- **Automatic Timestamps**: All JSON output includes RFC3339 timestamps (`@t` field)
- **PPX-driven**: Full compile-time parsing and code generation for zero runtime overhead
- **Operator Support**: Special operators for structure preservation (`@`) and stringification (`$`)
- **Format Specifiers**: Support for format strings like `{count:05d}`, `{value:.2f}`, `{flag:B}`
- **High Performance**: Comparable to hand-written Printf code

## Installation

```bash
opam install message-templates message-templates-ppx
```

Or add to your `dune-project`:

```dune
(depends
  message-templates
  message-templates-ppx
  ptime)
```

## Usage

Add the PPX to your dune file:

```dune
(executable
 (name myapp)
 (libraries message-templates yojson unix)
 (preprocess (pps message-templates-ppx)))
```

Note: The `unix` library is required for timestamp generation.

### Basic Example

```ocaml
let () =
  let username = "alice" in
  let ip_address = "192.168.1.1" in
  
  (* Template with automatic variable capture *)
  let msg, json = [%template "User {username} logged in from {ip_address}"] in
  
  Printf.printf "%s\n" msg;
  (* Output: User alice logged in from 192.168.1.1 *)
  
  Yojson.Safe.to_string json |> print_endline;
  (* Output: {"@t":"2026-01-31T23:54:42-00:00","@m":"User {username} logged in from {ip_address}",
              "username":"alice","ip_address":"192.168.1.1"} *)
```

### Operators

- `{var}` - Default: Standard variable substitution
- `{@var}` - Structure: Preserve as JSON structure
- `{$var}` - Stringify: Convert value to string representation

### Format Specifiers

Format specifiers work like Printf formats:

```ocaml
let count = 42 in
let score = 98.5 in
let active = true in

let msg, _ = [%template "Count: {count:05d}, Score: {score:.1f}, Active: {active:B}"] in
(* Output: Count: 00042, Score: 98.5, Active: true *)
```

Common format specifiers:
- `{var:d}` - Integer (decimal)
- `{var:05d}` - Integer with zero-padding
- `{var:f}` - Float
- `{var:.2f}` - Float with 2 decimal places
- `{var:B}` - Boolean
- `{var:s}` - String (default)

### Escaped Braces

Use doubled braces for literal braces:

```ocaml
let msg, _ = [%template "Use {{braces}} for literals"] in
(* Output: Use {braces}} for literals *)
```

## Architecture

The library uses a PPX rewriter that operates at compile time:

1. **Parse**: Template string parsed into parts using Angstrom
2. **Validate**: Variable existence checked against lexical scope
3. **Generate**: OCaml code generated for both string and JSON output
4. **Zero Overhead**: No runtime parsing - all work done at compile time

## JSON Output Structure

All log events include a timestamp in RFC3339 format:

```json
{
  "@t": "2026-01-31T23:54:42-00:00",
  "@m": "User {username} logged in from {ip_address}",
  "username": "alice",
  "ip_address": "192.168.1.1"
}
```

- `@t`: Timestamp in RFC3339 format (ISO 8601 with timezone) - follows CLEF convention
- `@m`: Message template (the original template string) - follows CLEF convention
- Additional fields: Captured variables from the template

The field names `@t` and `@m` follow the [CLEF (Compact Log Event Format)](https://github.com/serilog/serilog-formatting-compact) convention used by Serilog and Seq. This is not part of the Message Templates specification, which leaves output format field names implementation-dependent.

## Performance

Benchmark results (1 million iterations each):

```
PPX Simple Template:  0.061 seconds (16,403,928 ops/sec)
Printf Simple:        0.056 seconds (17,753,142 ops/sec)
String Concat:        0.036 seconds (27,416,081 ops/sec)

PPX with Formats:     0.586 seconds (1,706,083 ops/sec)
Printf with Formats:  0.356 seconds (2,812,759 ops/sec)

PPX JSON Output:      0.232 seconds (4,313,078 ops/sec)
```

The PPX-generated code has minimal overhead compared to hand-written Printf, with the benefit of compile-time validation and automatic JSON generation with timestamps.

## Testing

Run the test suite:

```bash
dune runtest
```

This runs:
- Parser unit tests (5 tests)
- PPX comprehensive tests (8 tests including timestamp validation)

## Examples

See the `examples/` directory:
- `basic.ml` - Simple usage examples with timestamps
- `comprehensive_dir/main.ml` - Advanced features demonstration

Run examples:

```bash
dune exec examples/basic.exe
dune exec examples/comprehensive_dir/main.exe
```

## Implementation Details

### Core Components

1. **Template Parser** (`lib/template_parser.ml`)
   - Angstrom-based parser for Message Templates syntax
   - Supports holes, operators, format specifiers, escaped braces

2. **PPX Rewriter** (`ppx/ppx_message_templates.ml`)
   - Compile-time template processing
   - Generates Printf-based string rendering
   - Generates Yojson-based structured output with timestamps

3. **Code Generator** (`ppx/code_generator.ml`)
   - Builds format strings for Printf
   - Applies type-specific JSON converters
   - Generates timestamp using Ptime

4. **Runtime Helpers** (`lib/runtime_helpers.ml`)
   - Type-generic string conversion using Obj module
   - Handles primitives, lists, tuples, and custom types

### Timestamp Generation

Timestamps are generated at runtime using:
- `Unix.gettimeofday()` for current time
- `Ptime.of_float_s` to convert to Ptime.t
- `Ptime.to_rfc3339` for RFC3339 formatting

This ensures accurate timestamps in the generated JSON output.

### Supported Types

The PPX works with any OCaml type:
- Primitives: `string`, `int`, `float`, `bool`
- Collections: `list`, `array`
- Custom types: automatically converted via runtime helper

## Compliance with Message Templates Specification

This implementation follows the Message Templates specification from https://messagetemplates.org/:

- ✅ Named property holes: `{name}`
- ✅ Positional property holes: `{0}`, `{1}`
- ✅ Escaped braces: `{{` and `}}`
- ✅ Operators: `@` for structure, `$` for stringification
- ✅ Format specifiers: `:format` syntax
- ✅ Alignment specifiers: `,width` syntax
- ✅ Timestamp field in structured output (uses CLEF `@t` convention)
- ✅ Message template field in structured output (uses CLEF `@m` convention)

## License

MIT

## Acknowledgments

This implementation follows the Message Templates specification from https://messagetemplates.org/
