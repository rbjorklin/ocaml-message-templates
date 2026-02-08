(** LogContext - ambient properties that flow across scopes

    Properties are stored per-domain using Domain.DLS, making this safe for use
    in multicore OCaml programs. Properties do NOT automatically flow between
    domains - use [export_context]/[import_context] for that. *)

(** Domain-local storage state for context properties *)
type context_state =
  { mutable context_stack: (string * Yojson.Safe.t) list
  ; mutable correlation_id_stack: string list }

(** Create a DLS key with initial empty state *)
let context_key : context_state Domain.DLS.key =
  Domain.DLS.new_key (fun () -> {context_stack= []; correlation_id_stack= []})
;;

(** Helper to get current domain's context *)
let get_state () = Domain.DLS.get context_key

(** Push a property onto the context stack *)
let push_property name value =
  let state = get_state () in
  state.context_stack <- (name, value) :: state.context_stack
;;

(** Pop the most recent property *)
let pop_property () =
  let state = get_state () in
  match state.context_stack with
  | [] -> ()
  | _ :: rest -> state.context_stack <- rest
;;

(** Get all current context properties *)
let current_properties () =
  let state = get_state () in
  state.context_stack
;;

(** Clear all context properties *)
let clear () =
  let state = get_state () in
  state.context_stack <- []
;;

(** Execute function with temporary property (auto-pops on exit) *)
let with_property name value f =
  push_property name value;
  Fun.protect ~finally:pop_property f
;;

(** Execute function with multiple temporary properties *)
let with_properties properties f =
  List.iter (fun (name, value) -> push_property name value) properties;
  Fun.protect
    ~finally:(fun () -> List.iter (fun _ -> pop_property ()) properties)
    f
;;

(** Create a scope that clears context on exit *)
let with_scope f =
  let state = get_state () in
  let previous_context = state.context_stack in
  let previous_correlation = state.correlation_id_stack in
  Fun.protect
    ~finally:(fun () ->
      state.context_stack <- previous_context;
      state.correlation_id_stack <- previous_correlation )
    f
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
let push_correlation_id id =
  let state = get_state () in
  state.correlation_id_stack <- id :: state.correlation_id_stack
;;

(** Pop the current correlation ID *)
let pop_correlation_id () =
  let state = get_state () in
  match state.correlation_id_stack with
  | [] -> ()
  | _ :: rest -> state.correlation_id_stack <- rest
;;

(** Get the current correlation ID if any *)
let get_correlation_id () =
  let state = get_state () in
  match state.correlation_id_stack with
  | [] -> None
  | id :: _ -> Some id
;;

(** Execute function with a correlation ID (auto-pops on exit) *)
let with_correlation_id id f =
  push_correlation_id id;
  Fun.protect ~finally:pop_correlation_id f
;;

(** Execute function with an auto-generated correlation ID *)
let with_correlation_id_auto f =
  let id = generate_correlation_id () in
  with_correlation_id id f
;;

(** {2 Cross-Domain Context} *)

(** Context that spans across domains (explicit opt-in) *)
type cross_domain_context =
  { properties: (string * Yojson.Safe.t) list
  ; correlation_id: string option }

(** Serialize current context for cross-domain transfer *)
let export_context () : cross_domain_context =
  let state = get_state () in
  { properties= state.context_stack
  ; correlation_id=
      ( match state.correlation_id_stack with
      | [] -> None
      | id :: _ -> Some id ) }
;;

(** Import context in a new domain *)
let import_context ctx f =
  let state = get_state () in
  let previous_context = state.context_stack in
  let previous_correlation = state.correlation_id_stack in
  state.context_stack <- ctx.properties;
  state.correlation_id_stack <-
    ( match ctx.correlation_id with
    | None -> []
    | Some id -> [id] );
  Fun.protect
    ~finally:(fun () ->
      state.context_stack <- previous_context;
      state.correlation_id_stack <- previous_correlation )
    f
;;
