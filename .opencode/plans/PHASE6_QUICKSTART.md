# Phase 6: Quick Start Guide

**Speed**: Read in 5 minutes, start coding in 10 minutes  
**Target**: Implementer who wants immediate action items

---

## TL;DR - Phase 6 in 30 Seconds

**Goal**: Make logging production-ready  
**Work**: 5 hours (5 sprints, 1 hour each)  
**Modules**: Build 5 new modules (async queue, metrics, shutdown, circuit breaker, memory)  
**Tests**: Add 20+ tests  
**Result**: 4x faster logging, observable, resilient, graceful shutdown  

---

## The Five Modules You'll Build

### 1️⃣ async_sink_queue (1.5 hours)
**What**: Non-blocking queue for I/O buffering  
**Why**: Console emit is 4.2μs, queue reduces to 1μs  
**How**: Mutex + circular buffer + background thread  
```ocaml
val create : config -> Sink.t -> t
val enqueue : t -> Log_event.t -> unit  (* non-blocking *)
val flush : t -> unit
```

### 2️⃣ metrics (1.5 hours)
**What**: Observable logging system  
**Why**: Can't see throughput, latency, errors currently  
**How**: Per-sink counters + latency percentiles  
```ocaml
val record_event : t -> sink_id:string -> latency_us:float -> unit
val get_sink_metrics : t -> string -> sink_metrics option
val to_json : t -> Yojson.Safe.t
```

### 3️⃣ shutdown (0.5 hours)
**What**: Graceful shutdown protocol  
**Why**: Events lost on exit, no timeout protection  
**How**: Strategies (Immediate, Flush, Graceful) + timeout  
```ocaml
type shutdown_strategy = Immediate | Flush_pending | Graceful of float
val execute : t -> shutdown_strategy -> unit
```

### 4️⃣ circuit_breaker (0.5 hours)
**What**: Error recovery pattern  
**Why**: One broken sink breaks all logging  
**How**: State machine (Closed/Open/Half_open)  
```ocaml
val call : t -> (unit -> unit) -> bool  (* true if success *)
```

### 5️⃣ memory_tracking (1 hour)
**What**: Memory limits  
**Why**: Queue can grow unbounded  
**How**: Track bytes, drop oldest when over limit  
```ocaml
val record_enqueue : t -> bytes:int -> unit
val is_over_limit : t -> bool
```

---

## 5-Minute Reading Plan

### Option A: Fast Track (Just code)
→ Read: PHASE6_IMPLEMENTATION_GUIDE.md  
→ Sections: "6 Modules to Implement" only  
→ Time: 20 minutes, then start coding  

### Option B: Complete Understanding
→ Read: PHASE6_INDEX.md (this tells you structure)  
→ Read: PHASE6_IMPLEMENTATION_GUIDE.md (how to build)  
→ Skim: PHASE6_ANALYSIS.md (for design questions)  
→ Time: 45 minutes, then start coding  

### Option C: Full Deep Dive
→ Read all 5 documents in order  
→ Take notes on each module  
→ Plan your testing approach  
→ Time: 2 hours, then start coding  

---

## Now: Start Coding

### Step 1: Create async_sink_queue.mli (5 min)

**File**: `lib/async_sink_queue.mli`

Copy from PHASE6_IMPLEMENTATION_GUIDE.md section "async_sink_queue.mli"

### Step 2: Create async_sink_queue.ml (30 min)

**File**: `lib/async_sink_queue.ml`

**Template** (from guide):
```ocaml
type t = {
  mutable events: Log_event.t option array;
  mutable head: int;
  mutable tail: int;
  max_size: int;
  config: config;
  lock: Mutex.t;
  (* ... *)
}

let create config sink = { ... }

let enqueue t event =
  Mutex.lock t.lock;
  (* Add to queue, drop oldest if full *)
  Mutex.unlock t.lock
```

### Step 3: Test It (20 min)

**File**: `test/test_phase6_queue.ml`

```ocaml
let test_enqueue () =
  let queue = Async_sink_queue.create default_config sink in
  Async_sink_queue.enqueue queue event;
  assert (Async_sink_queue.get_queue_depth queue = 1)

let () = run "Queue Tests" [...]
```

### Step 4: Repeat for Other Modules

Repeat above for:
- metrics (1.5 hours)
- shutdown (0.5 hours)
- circuit_breaker (0.5 hours)
- memory_tracking (1 hour)

---

## Build & Test

```bash
# Build
dune build

# Test
dune runtest

# Verify no regressions
# Should still see 63+ passing tests

# Benchmark
dune exec benchmarks/benchmark.exe -- -ascii -q 1
# Check for improvement (queue emit < 1μs)
```

---

## Key Files to Understand First

**Current logger implementation**:
- `lib/logger.ml` (99-125) - Core write method
- `lib/composite_sink.ml` - How sinks are composed

**Current limitations**:
- `lib/console_sink.ml` (59-70) - Blocking flush
- `lib/file_sink.ml` (127-136) - Sync emit

**Integration points**:
- `lib/configuration.ml` (40-54) - Config builder
- `lib/log.ml` - Global logger interface

---

## 5-Minute Reference Card

| Need | File | Section |
|------|------|---------|
| Module interface | PHASE6_IMPLEMENTATION_GUIDE.md | "Phase 6 Modules" |
| Algorithm | PHASE6_IMPLEMENTATION_GUIDE.md | Each module's "Implementation Strategy" |
| Test template | PHASE6_IMPLEMENTATION_GUIDE.md | "Testing Strategy" |
| Integration | PHASE6_IMPLEMENTATION_GUIDE.md | "Integration Points" |
| Design question | PHASE6_ANALYSIS.md | Search requirement |
| Code location | PHASE6_CURRENT_LIMITATIONS.md | File + line numbers |
| Timeline | PHASE6_COLLECTION_SUMMARY.md | "Implementation Timeline" |

---

## Success Checklist

After each module:
- [ ] Compiles: `dune build`
- [ ] Tests pass: `dune exec test/test_phase6.exe`
- [ ] 63+ existing tests still pass: `dune runtest`
- [ ] No compiler warnings

Final check:
- [ ] All 5 modules implemented
- [ ] 20+ tests added
- [ ] Zero regressions
- [ ] Performance improved (benchmarks)

---

## Key Code Pattern You'll Use

```ocaml
(* Thread-safe queue pattern - used in multiple modules *)
let mutex = Mutex.create ()

let enqueue event =
  Mutex.lock mutex;
  try
    (* Do work *)
    Mutex.unlock mutex
  with exn ->
    Mutex.unlock mutex;
    raise exn
```

---

## Common Gotchas

**Gotcha 1**: Forgetting to unlock mutex  
→ Use try/finally pattern (shown above)

**Gotcha 2**: Metrics overhead too high  
→ Use sampling or approximate percentiles

**Gotcha 3**: Background thread never exits  
→ Add shutdown flag, join thread on close

**Gotcha 4**: Circuit breaker leaks state  
→ Reset timeout implemented properly

**Gotcha 5**: Memory tracking not accurate  
→ Count bytes of actual event objects

---

## Questions While Coding?

**"What's the exact interface?"**  
→ PHASE6_IMPLEMENTATION_GUIDE.md → "Phase 6 Modules"

**"What should my algorithm do?"**  
→ PHASE6_IMPLEMENTATION_GUIDE.md → Module name → "Algorithm" section

**"What tests should I write?"**  
→ PHASE6_IMPLEMENTATION_GUIDE.md → "Testing Strategy"

**"Why are we doing this?"**  
→ PHASE6_ANALYSIS.md → Section on that feature

**"What's the current problem?"**  
→ PHASE6_CURRENT_LIMITATIONS.md → Issue number

---

## Timeline Tracker

Use this to track your progress:

```
Sprint 1: async_sink_queue
  [ ] .mli created
  [ ] .ml implemented
  [ ] 5+ tests pass
  [ ] Existing tests still pass
  [ ] Time: 1.5 hours

Sprint 2: metrics
  [ ] .mli created
  [ ] .ml implemented
  [ ] 5+ tests pass
  [ ] Existing tests still pass
  [ ] Time: 1.5 hours

Sprint 3: shutdown + circuit_breaker
  [ ] Both .mli created
  [ ] Both .ml implemented
  [ ] 4+ tests pass
  [ ] Existing tests still pass
  [ ] Time: 1 hour

Sprint 4: memory_tracking
  [ ] .mli created
  [ ] .ml implemented
  [ ] 3+ tests pass
  [ ] Existing tests still pass
  [ ] Time: 1 hour

Sprint 5: Integration + verification
  [ ] Configuration.ml updated
  [ ] Logger.ml updated
  [ ] Composite_sink.ml updated
  [ ] All 20+ tests pass
  [ ] All 63+ existing tests pass
  [ ] Benchmarks show improvement
  [ ] Time: 1 hour

TOTAL: 5 hours
```

---

## One-Liner Reference

**Async_sink_queue**: Mutex + circular buffer + thread = non-blocking queue  
**Metrics**: Hashtbl of per-sink counters = observability  
**Shutdown**: Registered handlers + timeout = graceful exit  
**Circuit_breaker**: State machine (Closed/Open/Half) = error recovery  
**Memory_tracking**: Track bytes, drop old = memory limits  

---

## You're Ready!

**Next Action**:
1. Open PHASE6_IMPLEMENTATION_GUIDE.md
2. Start with async_sink_queue.mli
3. Implement following the exact interface
4. Test as you go
5. Repeat for other modules

**Estimated Time**: 5 hours  
**Difficulty**: Medium (threading, some algorithms)  
**Support**: All information in Phase 6 docs  

---

**Go build it!** 🚀

When complete, you'll have:
- ✅ 4x faster logging (1μs vs 4.2μs)
- ✅ Observable system (metrics)
- ✅ Graceful shutdown (timeout protected)
- ✅ Error recovery (circuit breaker)
- ✅ Memory safe (limits + cleanup)

And the library will be **production-ready**!
