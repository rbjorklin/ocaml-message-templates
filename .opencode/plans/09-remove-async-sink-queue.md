# Plan 9: Remove Async_sink_queue Module

## Status
**Priority:** HIGH  
**Estimated Effort:** 1-2 hours  
**Risk Level:** Low (removing dead code)

## Problem Statement

The `Async_sink_queue` module is **dead code** that is not integrated with the project's async architecture:

### Current Situation

1. **Not exported** - Missing from `lib/messageTemplates.ml` exports
2. **Not used by Lwt** - `message-templates-lwt` uses `Lwt.t` promises, not this queue
3. **Not used by Eio** - `message-templates-eio` uses fiber-based concurrency, not this queue
4. **Not used by Configuration** - `Configuration` module creates sinks directly
5. **Only used in tests** - `test_phase6_async_queue.ml` tests a module nothing else uses

### Architecture Mismatch

The current implementation uses **plain OCaml Threads** with busy-waiting:
```ocaml
let rec sleep_loop () =
  let elapsed = Unix.gettimeofday () -. start in
  if elapsed < total_sleep then (
    Thread.delay sleep_chunk;  (* 10ms busy-wait *)
    ...
```

This doesn't integrate with either Lwt or Eio:

| Aspect | Lwt | Eio | Async_queue |
|--------|-----|-----|-------------|
| Concurrency | Promises (Lwt.t) | Fibers | Plain Threads |
| Blocking | Cooperative | Structured | OS threads |
| Integration | Hooks into Lwt_engine | Eio switch/fiber | None |

### Busy-Waiting Issues

Even if we fixed the busy-waiting (as suggested in Plan 5), the module would still:
- Use OS threads that don't compose with Lwt/Eio
- Duplicate functionality already provided by Lwt/Eio primitives
- Add maintenance burden for unused code

## Solution

Remove the `Async_sink_queue` module entirely. This is dead code elimination that:
- Reduces maintenance burden
- Eliminates confusion about which async model to use
- Follows the YAGNI principle

## Implementation Steps

### Step 1: Remove Source Files

**Files to delete:**
- `lib/async_sink_queue.ml`
- `lib/async_sink_queue.mli`

**Action:**
```bash
rm lib/async_sink_queue.ml lib/async_sink_queue.mli
```

### Step 2: Update Test Suite

**File:** `test/test_phase6_async_queue.ml`

**Action:** Delete the entire test file since it only tests the removed module.

```bash
rm test/test_phase6_async_queue.ml
```

### Step 3: Update Test Dune Configuration

**File:** `test/dune`

Locate the test configuration and remove `test_phase6_async_queue` from the names list.

**Example change:**
```scheme
;; BEFORE
(test
 (names
  test_level
  test_parser
  ...
  test_phase6_async_queue  ;; REMOVE THIS
  test_circuit_breaker))

;; AFTER
(test
 (names
  test_level
  test_parser
  ...
  test_circuit_breaker))
```

### Step 4: Verify No Remaining References

**Action:** Search for any remaining references to `Async_sink_queue`:

```bash
# Search in OCaml files
grep -r "Async_sink_queue" --include="*.ml" --include="*.mli" .

# Search in documentation
grep -r "async_sink_queue" --include="*.md" .

# Check if referenced in any dune files
grep -r "async_sink_queue" --include="dune" .
```

**Expected result:** No matches (or only in plan files and git history)

### Step 5: Build Verification

**Action:** Ensure the project builds without the removed files:

```bash
dune clean
dune build @install
```

**Expected:** Clean build with no "unbound module" or "missing file" errors.

### Step 6: Run Tests

**Action:** Run the test suite to ensure nothing is broken:

```bash
dune build @runtest
```

**Expected:** All tests pass (except possibly the removed async_queue tests).

### Step 7: Update Documentation

**Files to check:**
- `README.md` - Check for any mentions of async queue
- `MIGRATION.md` - Document the removal
- `CONFIGURATION.md` - Remove any async queue examples
- `AGENTS.md` - Remove references to async queue patterns

**Action:** Remove or update any documentation referencing `Async_sink_queue`.

## Alternative: Future Async Queue Support

If async queue functionality is needed in the future, implement it using the native primitives of each async library:

**For Lwt:**
```ocaml
(* Use Lwt_stream for buffering, Lwt_engine for timeouts *)
module Lwt_async_queue = struct
  type 'a t = {
    stream: 'a Lwt_stream.t;
    push: 'a option -> unit;
    flush_timer: Lwt_engine.event option;
  }
  (* Implementation using Lwt primitives *)
end
```

**For Eio:**
```ocaml
(* Use Eio.Stream for fiber-safe queues, Eio.Time for timeouts *)
module Eio_async_queue = struct
  type 'a t = {
    stream: 'a Eio.Stream.t;
    sw: Eio.Switch.t;
  }
  (* Implementation using Eio primitives *)
end
```

## Success Criteria

- [ ] `lib/async_sink_queue.ml` deleted
- [ ] `lib/async_sink_queue.mli` deleted
- [ ] `test/test_phase6_async_queue.ml` deleted
- [ ] `test/dune` updated (reference removed)
- [ ] No remaining references to `Async_sink_queue` in codebase
- [ ] Project builds successfully (`dune build @install`)
- [ ] All remaining tests pass (`dune build @runtest`)
- [ ] Documentation updated (no references to removed module)
- [ ] AGENTS.md updated to remove async queue patterns

## Migration Guide

### For Library Users

**No action required.** The `Async_sink_queue` module was never exported in the public API, so no user code can depend on it.

### Internal Code References

If any internal code (not found in analysis) references `Async_sink_queue`:

**Before:**
```ocaml
let queue = Async_sink_queue.create config sink_fn in
Async_sink_queue.enqueue queue event
```

**After (Lwt):**
```ocaml
(* Use Lwt's built-in async primitives instead *)
Lwt.async (fun () -> sink_fn event)
```

**After (Eio):**
```ocaml
(* Use Eio's fiber primitives instead *)
Eio.Fiber.fork ~sw (fun () -> sink_fn event)
```

**After (Synchronous):**
```ocaml
(* Call sink directly *)
sink_fn event
```

## Related Files

### To Delete
- `lib/async_sink_queue.ml`
- `lib/async_sink_queue.mli`
- `test/test_phase6_async_queue.ml`

### To Update
- `test/dune` - Remove test from names list
- `AGENTS.md` - Remove async queue patterns section
- Any documentation referencing async queue

### Related Plans (Superseded)
- `.opencode/plans/05-fix-async-queue-busy-waiting.md` - **DEPRECATED** by this plan

## Notes

- This is a **non-breaking change** - the module was never part of the public API
- The busy-waiting issue described in Plan 5 is moot - we're removing the problematic code entirely
- Lwt and Eio packages already implement their own async patterns
- If async queue is needed later, implement it within each async package using their native primitives
- Consider adding a note to Plan 5 explaining it has been superseded by this plan

## Post-Removal Verification Checklist

```bash
# 1. Verify files are deleted
ls lib/async_sink_queue.* 2>&1 | grep "No such file"
ls test/test_phase6_async_queue.ml 2>&1 | grep "No such file"

# 2. Verify no code references remain
grep -r "Async_sink_queue" lib/ test/ 2>/dev/null | wc -l  # Should be 0

# 3. Clean build
dune clean && dune build @install

# 4. Run tests
dune build @runtest

# 5. Check documentation
grep -i "async.*queue" README.md MIGRATION.md CONFIGURATION.md 2>/dev/null || echo "No references found"
```
