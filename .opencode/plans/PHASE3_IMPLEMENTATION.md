# Phase 3: Code Quality Improvements - Implementation Plan

**Date**: February 3, 2026
**Status**: In Progress
**Target**: Reduce duplication, improve consistency, better testing

---

## Overview

Phase 3 focuses on three improvements:
1. Extract common async abstractions (reduce duplication between Lwt/Eio)
2. Standardize configuration API documentation
3. Add property-based testing

---

## Task 3.1: Extract Common Async Abstractions

### Current State

The Lwt and Eio packages have significant code duplication (~60%):

**Duplicated Files**:
- `lwt_sink.ml` / `eio_sink.ml` (90% identical, except return types)
- `lwt_configuration.ml` / `eio_configuration.ml` (85% identical)
- `lwt_logger.ml` / `eio_logger.ml` (85% identical)
- `lwt_console_sink.ml` / `eio_console_sink.ml` (70% identical)
- `lwt_file_sink.ml` / `eio_file_sink.ml` (70% identical)

**Key Differences**:
- Lwt uses `unit Lwt.t` (promises), Eio uses `unit` (direct-style)
- Lwt uses `Lwt_list.iter_p` for parallel iteration, Eio uses `List.iter`
- File sink initialization: Lwt lazy, Eio eager
- Console sink: Lwt uses separate functions, Eio uses Eio-specific I/O

### Extraction Strategy

Create a **functor-based abstraction** parameterized by concurrency model:

```
lib/async_abstractions.mli/ml
├── Async_model (module type)
│   ├── type 'a t (promise/unit)
│   ├── val return : 'a -> 'a t
│   ├── val bind : 'a t -> ('a -> 'b t) -> 'b t
│   ├── val all : 'a t list -> 'a list t
│   └── val iter_p : ('a -> unit t) -> 'a list -> unit t
├── Make_sink (functor)
├── Make_configuration (functor)
└── Make_logger (functor)
```

### Implementation Steps

1. Create `lib/async_abstractions.mli`
   - Define `module type Async_model`
   - Define functor signatures: `Make_sink`, `Make_configuration`, `Make_logger`

2. Create `lib/async_abstractions.ml`
   - Implement functors using module type constraints

3. Refactor Lwt package
   - Create `message-templates-lwt/lib/lwt_model.ml` (Async_model impl for Lwt)
   - Use functors to generate lwt_sink, lwt_configuration, lwt_logger

4. Refactor Eio package
   - Create `message-templates-eio/lib/eio_model.ml` (Async_model impl for Eio)
   - Use functors to generate eio_sink, eio_configuration, eio_logger

5. Preserve public API
   - Keep existing module names and signatures
   - Internal use of functors only

### Files to Create

- `lib/async_abstractions.mli` (~150 lines)
- `lib/async_abstractions.ml` (~200 lines)
- `message-templates-lwt/lib/lwt_model.ml` (~30 lines)
- `message-templates-eio/lib/eio_model.ml` (~30 lines)

### Files to Refactor

- `message-templates-lwt/lib/lwt_sink.ml` → Use functor output
- `message-templates-lwt/lib/lwt_configuration.ml` → Use functor output
- `message-templates-lwt/lib/lwt_logger.ml` → Use functor output
- `message-templates-eio/lib/eio_sink.ml` → Use functor output
- `message-templates-eio/lib/eio_configuration.ml` → Use functor output
- `message-templates-eio/lib/eio_logger.ml` → Use functor output

### Benefits

- **Reduced Duplication**: ~2000 LOC reduced to ~500 LOC (75% reduction in async-specific code)
- **Maintainability**: Single source of truth for async patterns
- **Consistency**: Lwt and Eio features stay in sync
- **Extensibility**: Adding new async models (e.g., Async, Stdlib.Effect) becomes easy

### Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Functor complexity | Use simple, well-documented module types |
| Build time | Minimal impact (functors inlined) |
| API breakage | Keep public API identical |
| Performance | Direct-style code, no overhead |

---

## Task 3.2: Standardize Configuration API Documentation

### Current Issues

- `Configuration` module has 15+ chainable methods
- Poor discoverability of common patterns
- No quick-start guide in documentation

### Solution

1. **Add inline documentation** in `lib/configuration.ml`
   - Document each configuration method with example usage
   - Add links to common patterns

2. **Create CONFIGURATION.md guide**
   - Common setup patterns
   - Fluent API explanation
   - Examples for each method

3. **Improve method organization**
   - Group methods by category (sinks, filters, enrichment)
   - Add type aliases for clarity

### Expected Output

New file: `CONFIGURATION.md` with sections:
- Quick Start (5 most common patterns)
- Fluent API Overview
- Each sink type with examples
- Filter combinations
- Enrichment patterns
- Common mistakes

---

## Task 3.3: Add Property-Based Testing

### Current Testing

- Alcotest with 63+ specific test cases
- Good coverage of known cases
- Missing edge cases and random inputs

### New Testing with QCheck

1. **Random template generation**
   - Random variable names, escape sequences
   - Format specifiers combinations
   - Ensure parsing doesn't crash

2. **Random property preservation**
   - Log events retain all properties after filtering
   - Context properties merge correctly
   - Level ordering preserved through conversions

3. **Filter combinations**
   - All valid filter combinations work
   - Filter negation inverts results
   - AND/OR combinations are associative

4. **Configuration builder**
   - Configuration from any sequence of operations is valid
   - Order independence for non-sequential options

### Test Files to Create

- `test/test_qcheck_templates.ml` (~100 lines)
- `test/test_qcheck_filters.ml` (~80 lines)
- `test/test_qcheck_properties.ml` (~100 lines)

---

## Implementation Order

1. **First**: Extract async abstractions (3-4 hours)
   - Highest impact on code quality
   - Enables easier async model additions
   - Reduces maintenance burden

2. **Second**: Add property-based tests (1-2 hours)
   - Catches edge cases
   - Validates abstractions work
   - Relatively independent of other work

3. **Third**: Configuration documentation (1-1.5 hours)
   - Lower priority but improves UX
   - Can be done in parallel with first two

---

## Success Criteria

### 3.1: Async Abstractions
- [ ] All tests still pass
- [ ] Code duplication reduced by 70%+
- [ ] Public API unchanged
- [ ] Lwt and Eio packages maintain feature parity
- [ ] New async model easy to add (demonstrable with docs)

### 3.2: Configuration Documentation
- [ ] CONFIGURATION.md covers 80% of use cases
- [ ] All public methods documented with examples
- [ ] Quick-start guide is copy-paste ready

### 3.3: Property-Based Tests
- [ ] 3+ test modules with QCheck generators
- [ ] 50+ property-based tests total
- [ ] No regressions in existing tests
- [ ] Edge cases covered (empty templates, special chars, etc.)

---

## Estimated Timeline

| Task | Hours | Start | End |
|------|-------|-------|-----|
| 3.1 Setup & Research | 1 | Day 1 | Day 1 |
| 3.1 Implementation | 2.5 | Day 1 | Day 2 |
| 3.1 Testing & Debugging | 1 | Day 2 | Day 2 |
| 3.2 Documentation | 1.5 | Day 2 | Day 2 |
| 3.3 Property Tests | 2 | Day 2-3 | Day 3 |
| Verification & Fixes | 1 | Day 3 | Day 3 |

**Total**: ~9 hours (can be parallelized)

---

## Related Documents

- AGENTS.md - Project guidelines
- AMP_IMPROVEMENTS.md - Full improvement plan
- BUILD_FIX_SUMMARY.md - Recently fixed issues
