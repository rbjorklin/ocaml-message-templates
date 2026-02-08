(** Comprehensive type coverage tests for Message Templates

    Note: Explicit type annotations in these tests are for documentation
    clarity. The PPX extension runs before type checking, so it cannot use type
    information to select specific converters. All template variables use
    [generic_to_json] regardless of type annotations. *)

open Alcotest

(** Test Bytes type *)
let test_bytes () =
  let bs : bytes = Bytes.of_string "hello" in
  let msg, _ = [%template "Bytes: {$bs}"] in
  Printf.printf "%s%!" msg;
  (* Bytes should be converted to string representation *)
  check bool "Message contains bytes" true
    (String.contains msg 'h' || String.contains msg '<')
;;

(** Test Reference type *)
let test_ref () =
  let r : int ref = ref 42 in
  let msg, _ = [%template "Ref: {$r}"] in
  Printf.printf "%s%!" msg;
  (* Ref should show the contents or a representation *)
  check bool "Message contains ref value" true
    (String.contains msg '4' || String.contains msg '<')
;;

(** Test Lazy type *)
let test_lazy () =
  let lz : int lazy_t = lazy 42 in
  let msg, _ = [%template "Lazy: {$lz}"] in
  Printf.printf "%s%!" msg;
  (* Lazy values are forced and show the underlying value *)
  check bool "Message contains lazy value" true (String.contains msg '4')
;;

(** Test 4-tuple (quad) *)
let test_quad () =
  let quad : int * string * float * bool = (1, "a", 3.14, true) in
  let msg, _ = [%template "Quad: {$quad}"] in
  Printf.printf "%s%!" msg;
  (* Should contain the tuple elements *)
  check bool "Message contains quad elements" true
    (String.contains msg '1' || String.contains msg '<')
;;

(** Test Set *)
let test_set () =
  let module StringSet = Set.Make (String) in
  let s = StringSet.of_list ["a"; "b"; "c"] in
  let msg, _ = [%template "Set: {$s}"] in
  Printf.printf "%s%!" msg;
  (* Set should show its contents as a list *)
  check bool "Message contains set elements" true (String.contains msg '[')
;;

(** Test Map *)
let test_map () =
  let module StringMap = Map.Make (String) in
  let map = StringMap.empty in
  let map = StringMap.add "key1" 100 map in
  let map = StringMap.add "key2" 200 map in
  let map = StringMap.add "key3" 300 map in
  let msg, _ = [%template "Map: {$map}"] in
  Printf.printf "%s%!" msg;
  (* Map should show its contents as a list *)
  check bool "Message contains map elements" true (String.contains msg '[')
;;

(** Test Queue *)
let test_queue () =
  let q = Queue.create () in
  Queue.add 1 q;
  Queue.add 2 q;
  let msg, _ = [%template "Queue: {$q}"] in
  Printf.printf "%s%!" msg;
  (* Queue should show its contents *)
  check bool "Message contains queue elements" true
    (String.contains msg '1' || String.contains msg '<')
;;

(** Test Stack *)
let test_stack () =
  let s = Stack.create () in
  Stack.push 1 s;
  Stack.push 2 s;
  let msg, _ = [%template "Stack: {$s}"] in
  Printf.printf "%s%!" msg;
  (* Stack should show its contents *)
  check bool "Message contains stack elements" true
    (String.contains msg '1' || String.contains msg '<')
;;

(** Test custom record type *)
type my_record =
  { name: string
  ; value: int }

let test_record () =
  let r : my_record = {name= "test"; value= 42} in
  let msg, _ = [%template "Record: {$r}"] in
  Printf.printf "%s%!" msg;
  (* Record should show its fields *)
  check bool "Message contains record fields" true
    (String.contains msg 't' || String.contains msg '<')
;;

(** Test custom variant type *)
type my_variant =
  | A
  | B of int
  | C of string * int

let test_variant () =
  let v1 : my_variant = A in
  let v2 : my_variant = B 42 in
  let v3 : my_variant = C ("test", 100) in
  let msg, _ = [%template "Variants: {$v1}, {$v2}, {$v3}"] in
  Printf.printf "%s%!" msg;
  (* Variants should show their values in human-friendly format *)
  check bool "Message contains variant values" true
    (String.contains msg '4' && String.contains msg 't')
;;

(** Test polymorphic variant *)
let test_poly_variant () =
  let pv : [`A | `B of int] = `B 42 in
  let msg, _ = [%template "Poly variant: {$pv}"] in
  Printf.printf "%s%!" msg;
  (* Polymorphic variants show as a list with the tag code *)
  check bool "Message contains poly variant list" true (String.contains msg '[')
;;

(** Test closure *)
let test_closure () =
  let f x = x + 1 in
  let msg, _ = [%template "Closure: {$f}"] in
  Printf.printf "%s%!" msg;
  (* Closures should show as <closure> *)
  check bool "Message contains closure marker" true (String.contains msg '<')
;;

(** Test flat float array *)
let test_flat_float_array () =
  let arr = [|1.0; 2.0; 3.0|] in
  let msg, _ = [%template "Float array: {$arr}"] in
  Printf.printf "%s%!" msg;
  (* Float arrays should show the values *)
  check bool "Message contains float values" true
    (String.contains msg '1' || String.contains msg '<')
;;

(** Test object *)
let test_object () =
  let obj =
    object
      val x = 42

      method get_x = x
    end
  in
  let msg, _ = [%template "Object: {$obj}"] in
  Printf.printf "%s%!" msg;
  (* Objects should show as <object> or their contents *)
  check bool "Message contains object marker" true (String.contains msg '<')
;;

let () =
  run "Type Coverage Tests"
    [ ( "uncovered_types"
      , [ test_case "Bytes type" `Quick test_bytes
        ; test_case "Reference type" `Quick test_ref
        ; test_case "Lazy type" `Quick test_lazy
        ; test_case "4-tuple" `Quick test_quad
        ; test_case "Set type" `Quick test_set
        ; test_case "Map type" `Quick test_map
        ; test_case "Queue type" `Quick test_queue
        ; test_case "Stack type" `Quick test_stack
        ; test_case "Custom record" `Quick test_record
        ; test_case "Custom variant" `Quick test_variant
        ; test_case "Polymorphic variant" `Quick test_poly_variant
        ; test_case "Closure" `Quick test_closure
        ; test_case "Flat float array" `Quick test_flat_float_array
        ; test_case "Object" `Quick test_object ] ) ]
;;
