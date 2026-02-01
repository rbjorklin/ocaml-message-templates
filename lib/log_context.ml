(** LogContext - ambient properties that flow across async boundaries *)

(** Thread-local storage for context properties using a reference to a list *)
let context_stack : (string * Yojson.Safe.t) list ref = ref []

(** Push a property onto the context stack *)
let push_property name value =
  context_stack := (name, value) :: !context_stack

(** Pop the most recent property *)
let pop_property () =
  match !context_stack with
  | [] -> ()
  | _ :: rest -> context_stack := rest

(** Get all current context properties *)
let current_properties () =
  !context_stack

(** Clear all context properties *)
let clear () =
  context_stack := []

(** Execute function with temporary property (auto-pops on exit) *)
let with_property name value f =
  push_property name value;
  try
    let result = f () in
    pop_property ();
    result
  with e ->
    pop_property ();
    raise e

(** Execute function with multiple temporary properties *)
let with_properties properties f =
  List.iter (fun (name, value) -> push_property name value) properties;
  try
    let result = f () in
    List.iter (fun _ -> pop_property ()) properties;
    result
  with e ->
    List.iter (fun _ -> pop_property ()) properties;
    raise e

(** Create a scope that clears context on exit *)
let with_scope f =
  let previous = !context_stack in
  try
    let result = f () in
    context_stack := previous;
    result
  with e ->
    context_stack := previous;
    raise e
