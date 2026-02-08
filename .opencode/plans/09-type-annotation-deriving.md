# Plan 9: Type Annotation and Deriving Approach for Obj Removal

## Status

**Priority:** HIGH  
**Estimated Effort:** 6-8 hours  
**Risk Level:** Medium (requires PPX modifications, but maintains backward compatibility)  
**Depends On:** Plan 2 (Remove Obj Usage)

## Problem Statement

The current implementation relies on `Obj` module runtime type inspection as a fallback when compile-time type detection fails. We need a type-safe alternative that:

1. Leverages explicit type annotations when available
2. Supports automatic converter derivation for custom types
3. Maintains convenience for users (minimal boilerplate)
4. Removes all Obj module usage

## Solution Overview

The "Type Annotation + Deriving" approach combines three mechanisms:

1. **Enhanced PPX Type Detection**: Better leverage of type annotations in scope
2. **Convention-Based Converter Resolution**: Auto-discover `to_json`/`of_json` functions following naming conventions
3. **PPX Deriving Support**: Generate converters automatically via `[@@deriving converter]`

## Architecture

```
User Code with Type Annotation
            |
            v
    +-------------------+
    |  PPX Type Checker |
    |  - Local let type  |
    |  - Module lookup   |
    |  - Convention match|
    +-------------------+
            |
    +-------+--------+
    |                |
  Known Type      Unknown Type
    |                |
    v                v
Direct Code     +------------------+
Generation      | Deriving Enabled?|
                +--------+---------+
                         |
              +----------+-----------+
              |                      |
            Yes                     No
              |                      |
              v                      v
    +------------------+    +------------------+
    | Generate Deriving|    | Emit Compile-Time|
    | Converter Code   |    | Error with Hint  |
    +------------------+    +------------------+
```

## Implementation Steps

### Step 1: Enhanced Type Detection in PPX

**File:** `ppx/scope_analyzer.ml` (enhancements)

Currently `find_variable` returns `core_type option`. We need to enhance it to:

1. Extract type information from local scope annotations
2. Look up module signatures for external types
3. Track type aliases

```ocaml
(* Enhanced scope entry *)
type scope_entry = {
  name: string;
  type_opt: core_type option;
  source: type_source;  (* Local_let, Parameter, External_module, etc. *)
}

(* Try harder to resolve type from annotations *)
let rec resolve_type ~loc scope name =
  match find_variable scope name with
  | Some {ptyp_desc= Ptyp_constr (lid, args); _} ->
      (* Check if this is a local type alias *)
      expand_type_alias scope lid args
  | Some {ptyp_desc= Ptyp_poly (_, ty); _} ->
      (* Handle polymorphic types *)
      resolve_type ~loc scope ty
  | None ->
      (* Try to find converter in scope based on naming convention *)
      find_converter_by_convention scope name
```

### Step 2: Convention-Based Converter Resolution

**File:** `ppx/code_generator.ml` (new function)

Implement a convention where types automatically get converters:

```ocaml
(* For a type `user`, look for `user_to_json` in scope *)
let find_convention_converter ~loc scope (ty : core_type) =
  match ty.ptyp_desc with
  | Ptyp_constr ({txt= Lident type_name; _}, []) ->
      (* Simple type like `user` -> look for `user_to_json` *)
      let converter_name = type_name ^ "_to_json" in
      if Scope_analyzer.has_binding scope converter_name then
        Some (evar ~loc converter_name)
      else
        None
  | Ptyp_constr ({txt= Ldot (mod_path, type_name); _}, []) ->
      (* Module-qualified type like `User.t` -> look for `User.to_json` or `User.t_to_json` *)
      let converter_lid = Ldot (mod_path, "to_json") in
      if Scope_analyzer.has_module_binding scope converter_lid then
        Some (pexp_ident ~loc {txt= converter_lid; loc})
      else
        None
  | _ -> None
```

### Step 3: Update Code Generator to Use Conventions

**File:** `ppx/code_generator.ml` (modify `yojson_of_value`)

```ocaml
let rec yojson_of_value ~loc (expr : expression) (ty : core_type option) =
  match ty with
  | Some {ptyp_desc= Ptyp_constr ({txt= Lident "string"; _}, []); _} ->
      [%expr `String [%e expr]]
  (* ... existing primitive cases ... *)
  | Some ty ->
      (* Try convention-based converter *)
      (match find_convention_converter ~loc scope ty with
      | Some converter ->
          [%expr [%e converter] [%e expr]]
      | None ->
          (* Type is known but no converter - emit helpful error *)
          Location.raise_errorf ~loc
            "MessageTemplates: No JSON converter found for type %a. \
             Add a %s_to_json function in scope, or derive it with [@@deriving converter]."
            Pprintast.core_type ty
            (type_name ty))
  | None ->
      (* No type information - require explicit annotation *)
      Location.raise_errorf ~loc
        "MessageTemplates: Cannot determine type for template variable. \
         Add an explicit type annotation like: (var : string)"
```

### Step 4: Implement Deriving Plugin

**File:** `ppx_deriving_message_templates/src/ppx_deriving_converter.ml` (new)

Create a standalone PPX deriving plugin:

```ocaml
(* Structure of the deriving plugin *)
let generate_converter type_decl =
  match type_decl.ptype_kind with
  | Ptype_record fields ->
      (* Generate record converter *)
      generate_record_converter type_decl fields
  | Ptype_variant constructors ->
      (* Generate variant converter *)
      generate_variant_converter type_decl constructors
  | Ptype_abstract ->
      (* Handle abstract types with manifest *)
      generate_abstract_converter type_decl
  | Ptype_open ->
      Location.raise_errorf ~loc:type_decl.ptype_loc
        "Open types not supported for converter deriving"

let generate_record_converter type_decl fields =
  let type_name = type_decl.ptype_name.txt in
  let converter_name = type_name ^ "_to_json" in
  
  (* Generate: let type_name_to_json r = `Assoc [...] *)
  [%str
    let [%p pvar ~loc converter_name] (r : [%t ptyp_constr ~loc (lid type_name) []]) =
      `Assoc [
        [%e elist ~loc (List.map (fun field ->
          [%expr [%e estring ~loc field.pld_name.txt],
                 [%e generate_field_conversion field] r.[%e field.pld_name.txt]])
          fields)]
      ]
  ]
```

### Step 5: Add Deriving Support to Core Types

**File:** `lib/types.ml` (add deriving attributes)

```ocaml
(* Example: Add deriving to existing types *)
type level =
  | Verbose
  | Debug
  | Information
  | Warning
  | Error
  | Fatal
[@@deriving converter]
(* Generates: val level_to_json : level -> Yojson.Safe.t *)

type 'a log_event = {
  timestamp: Ptime.t;
  level: level;
  template: string;
  message: string;
  properties: (string * Yojson.Safe.t) list;
  context: (string * Yojson.Safe.t) list;
}
[@@deriving converter]
```

### Step 6: Update Runtime Helpers

**File:** `lib/runtime_helpers.ml`

Remove Obj-based functions and enhance safe conversions:

```ocaml
(** Converter type for explicit conversions *)
type 'a t = 'a -> Yojson.Safe.t

module Converter = struct
  type 'a t = 'a -> Yojson.Safe.t
  
  let make f = f
  
  (* Primitives - same as existing Safe_conversions *)
  let string s = `String s
  let int i = `Int i
  let float f = `Float f
  (* ... etc ... *)
  
  (* Combinators for complex types *)
  let list elem_conv xs = `List (List.map elem_conv xs)
  let array elem_conv arr = `List (Array.to_list (Array.map elem_conv arr))
  let option elem_conv = function
    | None -> `Null
    | Some x -> elem_conv x
    
  (* For use with derived converters *)
  let record fields = `Assoc fields
  let variant name args = `Assoc [(name, `List args)]
end

(* Remove *)
[@@ocaml.deprecated "Use explicit converters or [@@deriving converter]"]
let generic_to_string _ = "<deprecated>"

[@@ocaml.deprecated "Use explicit converters or [@@deriving converter]"]
let generic_to_json _ = `String "<deprecated>"
```

### Step 7: Handle Stringify Operator

**File:** `ppx/code_generator.ml` (modify stringify handling)

```ocaml
| Stringify ->
    (* For {$var}, we need a string representation *)
    (* Option 1: Look for Showable or to_string function *)
    match find_stringifier ~loc scope ty with
    | Some stringifier ->
        [%expr `String ([%e stringifier] [%e expr])]
    | None ->
        (* Fall back to JSON then Yojson.to_string *)
        let json_expr = yojson_of_value ~loc expr ty in
        [%expr `String (Yojson.Safe.to_string [%e json_expr])]
```

### Step 8: Update PPX Log Levels

**File:** `ppx/ppx_log_levels.ml`

Currently always uses `generic_to_json`. Update to use type detection:

```ocaml
(* Current approach - always generic *)
[%expr Message_templates.Runtime_helpers.generic_to_json [%e var_expr]]

(* New approach - use type-aware conversion *)
let ty = Scope_analyzer.find_variable scope name in
let converter = Code_generator.yojson_of_value ~loc var_expr ty in
[%expr [%e converter]]
```

### Step 9: Add Helpful Error Messages

**File:** `ppx/code_generator.ml` (error handling)

```ocaml
let emit_type_error ~loc var_name ty =
  let hint = match ty with
  | None -> "Add an explicit type annotation: (var : string)"
  | Some t -> 
      Printf.sprintf "Define a converter: let %s_to_json = ..."
        (extract_type_name t)
  in
  Location.raise_errorf ~loc
    "MessageTemplates: Cannot convert '%s' to JSON. %s"
    var_name hint
```

### Step 10: Create Migration Guide

**File:** `MIGRATION.md` (new)

```markdown
## Migrating from Obj-based to Type-Safe Converters

### Before (v1.x with Obj)
```ocaml
type user = { id : int; name : string }
let user = { id = 42; name = "Alice" }
[%log.information "User {user}"]
```

### After (v2.0 type-safe)

#### Option 1: Derive Converter
```ocaml
type user = { id : int; name : string } [@@deriving converter]
let user = { id = 42; name = "Alice" }
[%log.information "User {user}"]
(* Uses automatically generated user_to_json *)
```

#### Option 2: Manual Converter
```ocaml
type user = { id : int; name : string }
let user_to_json u = 
  `Assoc [("id", `Int u.id); ("name", `String u.name)]
let user = { id = 42; name = "Alice" }
[%log.information "User {user}"]
(* Uses user_to_json from scope *)
```

#### Option 3: Type Annotation with Primitive
```ocaml
let (user_id : int) = 42
[%log.information "User {user_id}"]
(* Uses int_to_json - no custom converter needed *)
```
```

## Migration Scenarios

### Scenario 1: Custom Record Type

**Before:**
```ocaml
type point = { x : float; y : float }
let p = { x = 1.0; y = 2.0 }
[%log.debug "Point: {p}"]
```

**After (with deriving):**
```ocaml
type point = { x : float; y : float } [@@deriving converter]
let p = { x = 1.0; y = 2.0 }
[%log.debug "Point: {p}"]
```

**Generated code:**
```ocaml
let point_to_json p =
  `Assoc [("x", `Float p.x); ("y", `Float p.y)]
```

### Scenario 2: Variant Type

**Before:**
```ocaml
type status = Ok | Error of string
let s = Error "failed"
[%log.warning "Status: {s}"]
```

**After:**
```ocaml
type status = Ok | Error of string [@@deriving converter]
let s = Error "failed"
[%log.warning "Status: {s}"]
```

**Generated code:**
```ocaml
let status_to_json = function
  | Ok -> `String "Ok"
  | Error msg -> `Assoc [("Error", `String msg)]
```

### Scenario 3: Polymorphic Type

**Before:**
```ocaml
let items = [1; 2; 3]
[%log.debug "Items: {items}"]
```

**After:**
```ocaml
(* Works automatically - list is a known container *)
let items = [1; 2; 3]
[%log.debug "Items: {items}"]
(* Generates: `List (List.map int_to_json items) *)
```

### Scenario 4: Module-Qualified Type

**Before:**
```ocaml
module User = struct
  type t = { id : int }
end
let u = { User.id = 42 }
[%log.information "User: {u}"]
```

**After (Option 1 - convention):**
```ocaml
module User = struct
  type t = { id : int }
  let to_json u = `Assoc [("id", `Int u.id)]
end
let u = { User.id = 42 }
[%log.information "User: {u}"]
(* Finds User.to_json by convention *)
```

**After (Option 2 - deriving):**
```ocaml
module User = struct
  type t = { id : int } [@@deriving converter]
end
(* Generates User.t_to_json *)
```

## Testing Strategy

### Unit Tests

```ocaml
(* Test convention-based resolution *)
let test_convention_resolution () =
  let module M = struct
    type user = { id : int; name : string }
    let user_to_json u = 
      `Assoc [("id", `Int u.id); ("name", `String u.name)]
  end in
  let open M in
  let u = { id = 1; name = "test" } in
  (* This should compile and use user_to_json *)
  let _ = [%template "User: {u}"] in
  ()
```

### Deriving Tests

```ocaml
(* Test [@@deriving converter] for records *)
let test_deriving_record () =
  check yojson "record converter"
    (`Assoc [("x", `Float 1.0); ("y", `Float 2.0)])
    (point_to_json { x = 1.0; y = 2.0 })

(* Test [@@deriving converter] for variants *)
let test_deriving_variant () =
  check yojson "variant converter"
    (`Assoc [("Error", `String "msg")])
    (status_to_json (Error "msg"))
```

### Compile-Time Error Tests

```ocaml
(* This should produce a compile-time error *)
let test_missing_converter () =
  type opaque = Opaque of int
  let x = Opaque 42 in
  [%template "Value: {x}"]
  (* Error: No JSON converter found for type opaque.
     Add a opaque_to_json function in scope, or derive it. *)
```

## Success Criteria

- [ ] PPX detects types from explicit annotations
- [ ] Convention-based converter resolution works for simple types
- [ ] Deriving plugin generates correct converters for records
- [ ] Deriving plugin generates correct converters for variants
- [ ] Helpful error messages for missing converters
- [ ] All existing tests pass with new approach
- [ ] Migration guide complete with examples
- [ ] No Obj module usage in code paths

## Benefits

1. **Full Type Safety**: No runtime type inspection, all conversions verified at compile time
2. **Better Performance**: Direct function calls instead of runtime tag inspection
3. **Clear Errors**: Helpful compile-time messages instead of unexpected runtime behavior
4. **Extensibility**: Users can define custom converters for any type
5. **Ecosystem Integration**: Works with existing deriving plugins (yojson, show, etc.)

## Files to Modify

- `ppx/scope_analyzer.ml` - Enhanced type resolution
- `ppx/code_generator.ml` - Convention-based converter lookup
- `ppx/ppx_log_levels.ml` - Type-aware conversion
- `lib/runtime_helpers.ml` - Remove Obj, enhance Converter module
- `ppx_deriving_message_templates/` - New deriving plugin (optional)
- `lib/types.ml` - Add deriving attributes
- `dune-project` - Add deriving plugin dependency
- `README.md` - Update documentation
- `MIGRATION.md` - Create migration guide

## Related Plans

- Plan 2 (Remove Obj Usage) - This is the implementation of Option A from that plan
- Plan 6 (Add Comprehensive Tests) - Add tests for new converter system

## Notes

- The deriving plugin can be a separate package to avoid forcing the dependency on all users
- Convention-based resolution provides zero-overhead migration for many use cases
- Error messages should include examples to help users fix issues quickly
