# Plan 3: Fix Log_context Thread Safety for Multicore OCaml

## Status
**Priority:** HIGH  
**Estimated Effort:** 3-4 hours  
**Risk Level:** Medium (behavioral change in multi-domain scenarios)

## Problem Statement

`Log_context` uses global `ref` variables for context storage:

```ocaml
let context_stack : (string * Yojson.Safe.t) list ref = ref []
let correlation_id_stack : string list ref = ref []
```

### The Issue

In OCaml 5.x with multicore support:
- **Domains** share the same heap but run in parallel
- Global refs are shared across ALL domains
- `Log_context.with_property` is NOT thread-safe
- Context properties set in Domain A will be visible (and corrupted) by Domain B

### Impact

```ocaml
(* Domain 1 *)
Log_context.with_property "RequestId" (`String "req-1") (fun () ->
  (* Meanwhile, Domain 2 runs... *)
  Log_context.with_property "RequestId" (`String "req-2") (fun () ->
    (* Domain 1 might see "req-2" instead of "req-1"! *)
  )
)
```

This is a **silent data corruption bug** in any multi-domain application.

## Solution

Use `Domain.DLS` (Domain-Local Storage) for domain-safe context storage.

### Why Domain.DLS?

- Each domain gets its own independent storage
- No locking needed (domains don't share heap for DLS)
- Fibers within a domain share the same DLS (correct for structured concurrency)
- Compatible with both sync and async (Lwt/Eio) code within a domain

## Implementation Steps

### Step 1: Create Domain-Safe Context Storage

**File:** `lib/log_context.ml` (rewrite)

```ocaml
(** Domain-local storage for context properties *)
type context_state =
  { mutable context_stack: (string * Yojson.Safe.t) list
  ; mutable correlation_id_stack: string list }

(* Create a DLS key with initial empty state *)
let context_key : context_state Domain.DLS.key =
  Domain.DLS.new_key (fun () ->
    {context_stack= []; correlation_id_stack= []})

(* Helper to get current domain's context *)
let get_state () = Domain.DLS.get context_key
```

### Step 2: Rewrite Context Operations

```ocaml
(** Push a property onto the context stack *)
let push_property name value =
  let state = get_state () in
  state.context_stack <- (name, value) :: state.context_stack

(** Pop the most recent property *)
let pop_property () =
  let state = get_state () in
  match state.context_stack with
  | [] -> ()
  | _ :: rest -> state.context_stack <- rest

(** Get all current context properties *)
let current_properties () =
  let state = get_state () in
  state.context_stack

(** Clear all context properties *)
let clear () =
  let state = get_state () in
  state.context_stack <- []

(** Execute function with temporary property (auto-pops on exit) *)
let with_property name value f =
  push_property name value;
  Fun.protect ~finally:pop_property f

(** Execute function with multiple temporary properties *)
let with_properties properties f =
  List.iter (fun (name, value) -> push_property name value) properties;
  Fun.protect
    ~finally:(fun () ->
      List.iter (fun _ -> pop_property ()) properties)
    f

(** Create a scope that clears context on exit *)
let with_scope f =
  let state = get_state () in
  let previous_context = state.context_stack in
  let previous_correlation = state.correlation_id_stack in
  Fun.protect
    ~finally:(fun () ->
      state.context_stack <- previous_context;
      state.correlation_id_stack <- previous_correlation)
    f
```

### Step 3: Update Correlation ID Operations

```ocaml
(** Generate a new correlation ID (UUID-like format) *)
let generate_correlation_id () =
  let random_hex n =
    let chars = "0123456789abcdef" in
    let len = String.length chars in
    String.init n (fun _ -> chars.[Random.int len])
  in
  Printf.sprintf "%s-%s-%s-%s-%s" 
    (random_hex 8) (random_hex 4) (random_hex 4)
    (random_hex 4) (random_hex 12)

(** Push a correlation ID onto the stack *)
let push_correlation_id id =
  let state = get_state () in
  state.correlation_id_stack <- id :: state.correlation_id_stack

(** Pop the current correlation ID *)
let pop_correlation_id () =
  let state = get_state () in
  match state.correlation_id_stack with
  | [] -> ()
  | _ :: rest -> state.correlation_id_stack <- rest

(** Get the current correlation ID if any *)
let get_correlation_id () =
  let state = get_state () in
  match state.correlation_id_stack with
  | [] -> None
  | id :: _ -> Some id

(** Execute function with a correlation ID (auto-pops on exit) *)
let with_correlation_id id f =
  push_correlation_id id;
  Fun.protect ~finally:pop_correlation_id f

(** Execute function with an auto-generated correlation ID *)
let with_correlation_id_auto f =
  let id = generate_correlation_id () in
  with_correlation_id id f
```

### Step 4: Add Domain-Spanning Context Support (Optional Enhancement)

For contexts that need to propagate across domains:

```ocaml
(** Context that spans across domains (explicit opt-in) *)
type cross_domain_context =
  { properties: (string * Yojson.Safe.t) list
  ; correlation_id: string option }

(** Serialize current context for cross-domain transfer *)
let export_context () : cross_domain_context =
  let state = get_state () in
  { properties= state.context_stack
  ; correlation_id= 
      match state.correlation_id_stack with
      | [] -> None
      | id :: _ -> Some id }

(** Import context in a new domain *)
let import_context ctx f =
  let state = get_state () in
  let previous_context = state.context_stack in
  let previous_correlation = state.correlation_id_stack in
  state.context_stack <- ctx.properties;
  state.correlation_id_stack <- 
    match ctx.correlation_id with
    | None -> []
    | Some id -> [id];
  Fun.protect
    ~finally:(fun () ->
      state.context_stack <- previous_context;
      state.correlation_id_stack <- previous_correlation)
    f
```

### Step 5: Add Eio Fiber-Local Storage Support (Future Enhancement)

For Eio fiber-local storage (when needed):

```ocaml
(* In a future Eio-specific module *)
module Eio_context = struct
  (* Eio's cancellation context can store fiber-local data *)
  type ctx = Log_context.t

  let with_property_eio name value f =
    Eio.Fiber.finally
      (fun () -> 
        Log_context.push_property name value;
        f ())
      ~finally:Log_context.pop_property
end
```

### Step 6: Update Interface File

**File:** `lib/log_context.mli`

```ocaml
(** LogContext - ambient properties that flow across scopes

    Properties are stored per-domain using Domain.DLS, making this safe
    for use in multicore OCaml programs. Properties do NOT automatically
    flow between domains - use [export_context]/[import_context] for that.
*)

(** Push a property onto the context stack *)
val push_property : string -> Yojson.Safe.t -> unit

(** Pop the most recent property *)
val pop_property : unit -> unit

(** Get all current context properties *)
val current_properties : unit -> (string * Yojson.Safe.t) list

(** Clear all context properties *)
val clear : unit -> unit

(** Execute function with temporary property (auto-pops on exit) *)
val with_property : string -> Yojson.Safe.t -> (unit -> 'a) -> 'a

(** Execute function with multiple temporary properties *)
val with_properties : (string * Yojson.Safe.t) list -> (unit -> 'a) -> 'a

(** Create a scope that clears context on exit *)
val with_scope : (unit -> 'a) -> 'a

(** Generate a new correlation ID (UUID-like format) *)
val generate_correlation_id : unit -> string

(** Push a correlation ID onto the stack *)
val push_correlation_id : string -> unit

(** Pop the current correlation ID *)
val pop_correlation_id : unit -> unit

(** Get the current correlation ID if any *)
val get_correlation_id : unit -> string option

(** Execute function with a correlation ID (auto-pops on exit) *)
val with_correlation_id : string -> (unit -> 'a) -> 'a

(** Execute function with an auto-generated correlation ID *)
val with_correlation_id_auto : (unit -> 'a) -> 'a

(** {2 Cross-Domain Context} *)

type cross_domain_context
(** Opaque type for context that can be passed between domains *)

(** Serialize current context for cross-domain transfer *)
val export_context : unit -> cross_domain_context

(** Import context in a new domain *)
val import_context : cross_domain_context -> (unit -> 'a) -> 'a
```

## Testing Strategy

### 1. Domain Safety Tests

```ocaml
(** Test that contexts are isolated per-domain *)
let test_domain_isolation () =
  let domain1_result = ref None in
  let domain2_result = ref None in

  Log_context.with_property "key" (`String "domain1") (fun () ->
    let d1 = Domain.spawn (fun () ->
      Log_context.with_property "key" (`String "domain1_inner") (fun () ->
        domain1_result := Some (Log_context.current_properties ())
      )
    ) in

    let d2 = Domain.spawn (fun () ->
      Log_context.with_property "key" (`String "domain2") (fun () ->
        domain2_result := Some (Log_context.current_properties ())
      )
    ) in

    Domain.join d1;
    Domain.join d2;

    (* Verify each domain saw its own value *)
    Alcotest.(check (option (list (pair string yojson)))) 
      "domain1 has its value"
      (Some [("key", `String "domain1_inner")])
      !domain1_result;

    Alcotest.(check (option (list (pair string yojson))))
      "domain2 has its value"
      (Some [("key", `String "domain2")])
      !domain2_result;

    (* Verify main domain still has its original value *)
    Alcotest.(check (list (pair string yojson)))
      "main domain unchanged"
      [("key", `String "domain1")]
      (Log_context.current_properties ())
  )
```

### 2. Correlation ID Isolation Tests

```ocaml
let test_correlation_id_isolation () =
  let results = Array.make 3 None in

  let d1 = Domain.spawn (fun () ->
    Log_context.with_correlation_id "corr-1" (fun () ->
      results.(0) <- Log_context.get_correlation_id ()
    )
  ) in

  let d2 = Domain.spawn (fun () ->
    Log_context.with_correlation_id "corr-2" (fun () ->
      results.(1) <- Log_context.get_correlation_id ()
    )
  ) in

  Domain.join d1;
  Domain.join d2;

  results.(2) <- Log_context.get_correlation_id ();

  Alcotest.(check (option string)) "domain1 corr" (Some "corr-1") results.(0);
  Alcotest.(check (option string)) "domain2 corr" (Some "corr-2") results.(1);
  Alcotest.(check (option string)) "main domain no corr" None results.(2)
```

### 3. Cross-Domain Context Transfer Tests

```ocaml
let test_cross_domain_transfer () =
  Log_context.with_property "trace_id" (`String "trace-123") (fun () ->
    Log_context.with_correlation_id "corr-abc" (fun () ->
      let ctx = Log_context.export_context () in

      let result = ref None in
      let d = Domain.spawn (fun () ->
        Log_context.import_context ctx (fun () ->
          result := Some (
            Log_context.current_properties (),
            Log_context.get_correlation_id ()
          )
        )
      ) in

      Domain.join d;

      Alcotest.(check (option (pair (list (pair string yojson)) (option string))))
        "context transferred"
        (Some ([("trace_id", `String "trace-123")], Some "corr-abc"))
        !result
    )
  )
```

### 4. Fiber Safety Tests (Eio/Lwt)

```ocaml
(* For Lwt *)
let test_lwt_fiber_safety () =
  let open Lwt.Syntax in

  Log_context.with_property "request_id" (`String "main") (fun () ->
    let* () = Lwt_unix.sleep 0.001 in
    (* After yield, context should still be there *)
    Alcotest.(check (list (pair string yojson)))
      "context preserved across Lwt yield"
      [("request_id", `String "main")]
      (Log_context.current_properties ());
    Lwt.return ()
  )
```

## Migration Guide

### Behavioral Changes

**Before:**
- Context was global across all threads/domains
- Setting context in one thread affected all others
- Not safe for multicore

**After:**
- Context is per-domain
- Each domain has isolated context
- Safe for multicore
- Requires explicit transfer between domains

### For Library Users

**Single-Domain Programs:**
No changes needed. Code continues to work identically.

**Multi-Domain Programs:**

**Before (buggy in multicore):**
```ocaml
let process_request request =
  Log_context.with_property "RequestId" request.id (fun () ->
    (* Spawn parallel processing *)
    let domains = List.map (fun chunk ->
      Domain.spawn (fun () -> process_chunk chunk)
    ) request.chunks in
    List.iter Domain.join domains
  )
```

**After (correct):**
```ocaml
let process_request request =
  Log_context.with_property "RequestId" request.id (fun () ->
    let ctx = Log_context.export_context () in
    let domains = List.map (fun chunk ->
      Domain.spawn (fun () ->
        Log_context.import_context ctx (fun () ->
          process_chunk chunk
        )
      )
    ) request.chunks in
    List.iter Domain.join domains
  )
```

## Success Criteria

- [ ] Domain.DLS used for context storage
- [ ] Context properly isolated per-domain
- [ ] Cross-domain context transfer works
- [ ] All existing tests pass (single-domain behavior unchanged)
- [ ] New multicore tests added and passing
- [ ] Documentation updated with multicore guidance
- [ ] No performance regression in single-domain case

## Related Files

- `lib/log_context.ml`
- `lib/log_context.mli`
- `test/test_logger.ml` (may need updates if tests assumed global state)
- `examples/*.ml` (update multi-domain examples)
- `README.md`

## Notes

- This change is **source-compatible** for single-domain programs
- Multi-domain programs that relied on global context were already buggy
- The `export_context`/`import_context` pattern is similar to Go's context propagation
