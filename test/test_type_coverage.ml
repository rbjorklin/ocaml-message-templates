(** Comprehensive type coverage tests for Message Templates

    NOTE: These tests previously relied on Obj module for runtime type
    inspection. With the migration to type-safe conversions, complex types now
    require explicit converters. This test file is kept for documentation
    purposes but most tests have been removed.

    For type-safe logging of custom types: 1. Define a converter: let
    my_type_to_json x = `Assoc [...] 2. Use the Log module directly: Log.info
    "msg" [("key", my_type_to_json value)] *)

open Alcotest

(** Test basic primitive types still work with explicit annotations *)
let test_primitives () =
  let (s : string) = "hello" in
  let (n : int) = 42 in
  let (f : float) = 3.14 in
  let (b : bool) = true in

  (* Use Converter module for explicit conversions *)
  let json_s = Message_templates.Runtime_helpers.Converter.string s in
  let json_n = Message_templates.Runtime_helpers.Converter.int n in
  let json_f = Message_templates.Runtime_helpers.Converter.float f in
  let json_b = Message_templates.Runtime_helpers.Converter.bool b in

  check bool "String converter works" true
    ( match json_s with
    | `String "hello" -> true
    | _ -> false );
  check bool "Int converter works" true
    ( match json_n with
    | `Int 42 -> true
    | _ -> false );
  check bool "Float converter works" true
    ( match json_f with
    | `Float 3.14 -> true
    | _ -> false );
  check bool "Bool converter works" true
    ( match json_b with
    | `Bool true -> true
    | _ -> false )
;;

(** Test Converter module with containers *)
let test_converter_containers () =
  let int_list = [1; 2; 3] in
  let int_array = [|1; 2; 3|] in
  let string_opt = Some "test" in

  let json_list =
    Message_templates.Runtime_helpers.Converter.list
      Message_templates.Runtime_helpers.Converter.int int_list
  in
  let json_array =
    Message_templates.Runtime_helpers.Converter.array
      Message_templates.Runtime_helpers.Converter.int int_array
  in
  let json_opt =
    Message_templates.Runtime_helpers.Converter.option
      Message_templates.Runtime_helpers.Converter.string string_opt
  in

  check bool "List converter works" true
    ( match json_list with
    | `List [`Int 1; `Int 2; `Int 3] -> true
    | _ -> false );
  check bool "Array converter works" true
    ( match json_array with
    | `List [`Int 1; `Int 2; `Int 3] -> true
    | _ -> false );
  check bool "Option converter works" true
    ( match json_opt with
    | `String "test" -> true
    | _ -> false )
;;

let () =
  run "Type Coverage Tests"
    [ ( "converter_module"
      , [ test_case "Primitive converters" `Quick test_primitives
        ; test_case "Container converters" `Quick test_converter_containers ] )
    ]
;;
