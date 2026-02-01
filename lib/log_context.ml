(** LogContext - ambient properties that flow across async boundaries *)

(** Thread-local storage for context properties using a reference to a list *)
let context_stack : (string * Yojson.Safe.t) list ref = ref []

(** Separate storage for correlation ID to ensure it's always available *)
let correlation_id_stack : string list ref = ref []

(** Push a property onto the context stack *)
let push_property name value = context_stack := (name, value) :: !context_stack

(** Pop the most recent property *)
let pop_property () =
  match !context_stack with
  | [] -> ()
  | _ :: rest -> context_stack := rest
;;

(** Get all current context properties *)
let current_properties () = !context_stack

(** Clear all context properties *)
let clear () = context_stack := []

(** Execute function with temporary property (auto-pops on exit) *)
let with_property name value f =
  push_property name value;
  try
    let result = f () in
    pop_property (); result
  with e -> pop_property (); raise e
;;

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
;;

(** Create a scope that clears context on exit *)
let with_scope f =
  let previous = !context_stack in
  let previous_correlation = !correlation_id_stack in
  try
    let result = f () in
    context_stack := previous;
    correlation_id_stack := previous_correlation;
    result
  with e ->
    context_stack := previous;
    correlation_id_stack := previous_correlation;
    raise e
;;

(** Generate a new correlation ID (UUID-like format) *)
let generate_correlation_id () =
  let random_hex n =
    let chars = "0123456789abcdef" in
    let len = String.length chars in
    String.init n (fun _ -> chars.[Random.int len])
  in
  Printf.sprintf "%s-%s-%s-%s-%s" (random_hex 8) (random_hex 4) (random_hex 4)
    (random_hex 4) (random_hex 12)
;;

(** Push a correlation ID onto the stack *)
let push_correlation_id id = correlation_id_stack := id :: !correlation_id_stack

(** Pop the current correlation ID *)
let pop_correlation_id () =
  match !correlation_id_stack with
  | [] -> ()
  | _ :: rest -> correlation_id_stack := rest
;;

(** Get the current correlation ID if any *)
let get_correlation_id () =
  match !correlation_id_stack with
  | [] -> None
  | id :: _ -> Some id
;;

(** Execute function with a correlation ID (auto-pops on exit) *)
let with_correlation_id id f =
  push_correlation_id id;
  try
    let result = f () in
    pop_correlation_id (); result
  with e -> pop_correlation_id (); raise e
;;

(** Execute function with an auto-generated correlation ID *)
let with_correlation_id_auto f =
  let id = generate_correlation_id () in
  with_correlation_id id f
;;
