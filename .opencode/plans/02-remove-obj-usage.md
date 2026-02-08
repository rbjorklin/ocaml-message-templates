# Plan 2: Remove or Secure Obj Module Usage

## Status
**Priority:** HIGH  
**Estimated Effort:** 4-6 hours  
**Risk Level:** High (behavioral changes, potential breaking changes)

## Problem Statement

`Runtime_helpers.generic_to_string` and `generic_to_json` use the `Obj` module for runtime type introspection:

```ocaml
let generic_to_string (type a) (v : a) : string =
  let module O = Obj in
  match O.tag repr with
  | 252 -> (O.obj repr : string)  (* Hardcoded tag for string *)
  | 253 -> string_of_float (O.obj repr : float)  (* Hardcoded tag for float *)
  ...
```

### Issues

1. **Compiler Version Fragility**: Tag values (252, 253, etc.) are OCaml implementation details that could change
2. **No Type Safety**: Bypasses OCaml's type system entirely
3. **Heuristic Set/Map Detection**: Relies on block size and tag to detect Set/Map trees - could misidentify other structures
4. **Limited Type Coverage**: Only handles primitives, lists, and Set/Map trees. Records, variants, and abstract types get generic "(field1, field2)" output

### Current Usage

1. **PPX Code Generator** - fallback when compile-time type detection fails:
```ocaml
| _ ->
    (* Fallback: use generic conversion for unknown types *)
    [%expr Message_templates.Runtime_helpers.generic_to_json [%e expr]]
```

2. **Stringify Operator** (`{$var}`) - always uses generic_to_string

3. **Runtime Template Rendering** - for user-provided property lists

## Solution Options

### Option A: Remove Obj Entirely (Recommended)

Require explicit type annotations or converters. Best for type safety.

**Pros:**
- Full type safety
- No compiler version dependencies
- Clear error messages

**Cons:**
- Breaking change - users must add type annotations
- Less convenient for quick debugging

### Option B: Compiler Version Detection

Keep Obj usage but add runtime checks to detect incompatible compiler versions.

**Pros:**
- Maintains current convenience
- Can provide warnings/errors early

**Cons:**
- Still relies on implementation details
- Adds complexity

### Option C: PPX-Only Solution

Move all type conversion to compile-time PPX, remove runtime generic functions.

**Pros:**
- Type-safe
- Zero runtime overhead for known types

**Cons:**
- Dynamic templates (user-provided strings) won't work
- Requires PPX for all logging

## Recommended Implementation (Option A)

### Step 1: Add Type-Safe Conversion Module

**File:** `lib/runtime_helpers.ml` (new safe conversions)

Create an explicit converter system:

```ocaml
module Converter = struct
  type 'a t = 'a -> Yojson.Safe.t

  let make f = f

  (* Primitives *)
  let string : string t = fun s -> `String s
  let int : int t = fun i -> `Int i
  let float : float t = fun f -> `Float f
  let bool : bool t = fun b -> `Bool b
  let int64 : int64 t = fun i -> `Intlit (Int64.to_string i)
  let int32 : int32 t = fun i -> `Intlit (Int32.to_string i)
  let nativeint : nativeint t = fun i -> `Intlit (Nativeint.to_string i)
  let char : char t = fun c -> `String (String.make 1 c)
  let unit : unit t = fun () -> `Null

  (* Containers *)
  let list : 'a t -> 'a list t = fun elem_conv lst ->
    `List (List.map elem_conv lst)

  let array : 'a t -> 'a array t = fun elem_conv arr ->
    `List (Array.to_list (Array.map elem_conv arr))

  let option : 'a t -> 'a option t = fun elem_conv opt ->
    match opt with
    | None -> `Null
    | Some v -> elem_conv v

  (* Result type *)
  let result : 'a t -> 'b t -> ('a, 'b) result t = fun ok_conv err_conv res ->
    match res with
    | Ok v -> `Assoc [("Ok", ok_conv v)]
    | Error e -> `Assoc [("Error", err_conv e)]

  (* Pairs and tuples *)
  let pair : 'a t -> 'b t -> ('a * 'b) t = fun a_conv b_conv (a, b) ->
    `List [a_conv a; b_conv b]

  let triple : 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t = 
    fun a_conv b_conv c_conv (a, b, c) ->
    `List [a_conv a; b_conv b; c_conv c]

  (* Polymorphic variant for "showable" types *)
  type showable = { to_string : unit -> string }

  let showable (type a) (module S : sig val to_string : a -> string end) : a t =
    fun v -> `String (S.to_string v)
end
```

### Step 2: Update PPX Code Generator

**File:** `ppx/code_generator.ml`

Change fallback behavior to emit a compile-time warning instead of using generic_to_json:

```ocaml
let rec yojson_of_value ~loc (expr : expression) (ty : core_type option) =
  match ty with
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "string"; _}, []); _} ->
      [%expr `String [%e expr]]
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "int"; _}, []); _} ->
      [%expr `Int [%e expr]]
  (* ... existing cases ... *)
  | _ ->
      (* Instead of falling back to generic_to_json, emit warning *)
      let warning_attr = 
        Attr.mk ~loc:{loc with loc_ghost=true}
          {txt="ppx.warning"; loc}
          (PStr [%str [@@@ocaml.warning "Cannot determine type for template variable. 
                       Add explicit type annotation or use Converter module."]])
      in
      [%expr `String "<unknown: add type annotation>"]
```

### Step 3: Deprecate generic_to_string/generic_to_json

**File:** `lib/runtime_helpers.ml`

Add deprecation warnings:

```ocaml
[@@ocaml.deprecated "Use Converter module with explicit type annotations"]
let generic_to_string (type a) (v : a) : string =
  (* existing implementation *)

[@@ocaml.deprecated "Use Converter module with explicit type annotations"]
let generic_to_json (type a) (v : a) : Yojson.Safe.t =
  (* existing implementation *)
```

### Step 4: Update PPX for Stringify Operator

**File:** `ppx/code_generator.ml`

For `{$var}` (Stringify operator), require explicit Showable converter:

```ocaml
| Stringify ->
    (* Instead of generic_to_string, require Showable *)
    match ty with
    | Some typ ->
        (* Try to detect if type has showable converter in scope *)
        [%expr `String (Message_templates.Runtime_helpers.Converter.to_string [%e expr])]
    | None ->
        Location.raise_errorf ~loc
          "Stringify operator {$var} requires explicit type annotation or Showable converter"
```

### Step 5: Add Converter Deriving Support (Optional Enhancement)

Create a `ppx_message_templates_converter` extension:

```ocaml
(* Users can write *)
type user = { id : int; name : string } [@@deriving converter]

(* Generated code *)
let user_to_json : user Converter.t = fun {id; name} ->
  `Assoc [("id", `Int id); ("name", `String name)]
```

### Step 6: Update Documentation

**File:** `README.md`, API docs

Document the Converter module:

```ocaml
(* Explicit type conversion *)
let user_id = 42 in
let user_name = "Alice" in
[%log.information "User {user_id} ({user_name}) logged in"]
  ~converters:[("user_id", Converter.int); ("user_name", Converter.string)]
```

### Step 7: Add Migration Helper

**File:** `lib/runtime_helpers.ml`

Provide a migration function that warns about removed functionality:

```ocaml
let generic_to_string_deprecated v =
  Printf.eprintf "WARNING: generic_to_string is deprecated and will be removed. \
                  Add explicit type annotation.\n%!)"
  generic_to_string v
```

## Testing Strategy

### 1. Type Safety Tests

```ocaml
(* Should compile and work *)
let test_explicit_converters () =
  let user_id = 42 in
  let properties = 
    [("user_id", Converter.int user_id)]
  in
  Alcotest.(check (list (pair string yojson))) "properties correct"
    [("user_id", `Int 42)] properties
```

### 2. PPX Compile-Time Tests

```ocaml
(* Should produce compile-time warning *)
[%template "Unknown {x}"]
(* Warning: Cannot determine type for template variable x *)

(* Should work without warning *)
let (x : int) = 42 in
[%template "Known {x}"]
```

### 3. Property-Based Tests

Verify converter round-tripping for supported types:

```ocaml
let test_roundtrip =
  QCheck.Test.make ~count:1000
    QCheck.int
    (fun i ->
      let json = Converter.int i in
      match json with
      | `Int j -> i = j
      | _ -> false)
```

## Migration Guide

### For Library Users

**Before (with Obj fallback):**
```ocaml
let user = { id = 42; name = "Alice" } in
[%log.information "User {user}"]
(* Output: "User (42, Alice)" via Obj introspection *)
```

**After (explicit conversion):**
```ocaml
type user = { id : int; name : string }

let user_to_json user =
  `Assoc [("id", `Int user.id); ("name", `String user.name)]

let user = { id = 42; name = "Alice" } in
Log.information "User {user}"
  [("user", user_to_json user)]

(* Or with PPX and explicit type *)
let (user : user) = { id = 42; name = "Alice" } in
[%log.information "User {user}"]
(* Requires user user_to_json to be in scope *)
```

### Breaking Changes

- `generic_to_string` and `generic_to_json` deprecated
- PPX extension requires explicit type annotations for unknown types
- Custom types need explicit converters

## Success Criteria

- [ ] Obj module usage removed or isolated with version detection
- [ ] Converter module implemented with full test coverage
- [ ] PPX emits helpful warnings for unknown types
- [ ] All existing tests updated to use explicit converters
- [ ] Documentation updated with migration guide
- [ ] Benchmark shows no performance regression

## Related Files

- `lib/runtime_helpers.ml`
- `lib/runtime_helpers.mli`
- `ppx/code_generator.ml`
- `test/test_type_coverage.ml`
- `README.md`
