---
description: 'Guidelines for building OCaml applications'
applyTo: '**/*.{ml,mli,dune,opam}'
---

# OCaml Development

## OCaml Instructions
- Use **OCaml 5.4.0** for new projects and target its features (multicore domains and effect handlers) only when libraries and runtime constraints are understood.
- Prefer **pure, total functions** and explicit use of `option` and `result` types instead of `null` or exceptions for ordinary control flow.
- Document module interfaces in `.mli` files and keep implementation details in `.ml` files.

## General Instructions
- Make only **high confidence** suggestions when reviewing code changes.
- Favor **clarity and maintainability**: explain *why* a design was chosen in comments, not just *what* it does.
- Handle edge cases explicitly and prefer typed encodings of invariants over runtime checks.
- For external libraries, add a short comment describing **purpose**, **scope**, and **compatibility** (OCaml version, dune/opam constraints).

## Naming Conventions
- **Module names**: PascalCase (e.g., `Http_client` becomes `Http_client` with file `http_client.ml` and module `Http_client`).  
- **Value and function names**: snake_case (e.g., `parse_request`, `compute_checksum`).  
- **Type names**: snake_case for type identifiers (e.g., `user_profile`), PascalCase for variant constructors (e.g., `Active`, `Inactive`).  
- **File names**: snake_case matching the primary module (e.g., `user_service.ml`, `user_service.mli`).  
- **Signature files**: use `.mli` to expose only the intended API; keep internal helpers unexposed.

## Formatting
- Use **dune fmt** with a project `.ocamlformat` file and enforce it in CI.
- Use **dune** formatting conventions for project files; keep `dune` files minimal and readable.
- Keep line lengths reasonable (e.g., 80–100 chars) and prefer small, focused functions.
- Prefer pattern matching over chained `if/else` when matching algebraic data types.
- Avoid partial functions like `List.hd` or `List.tl`; prefer safe accessors returning `option`.
- Use `let` bindings for clarity and avoid deeply nested expressions; prefer `let*`/`let+` when using monadic syntax with `ppx_let` or `Result`/`Lwt` helpers.
- Document public APIs with `(** ... *)` comments that `odoc` can render.

## Project Setup and Structure
- Use **opam** for package management and **dune** as the build system.
- Create a `dune-project` and explain the purpose of each top-level file (`dune-project`, `dune`, `opam`, `.ocamlformat`, `README.md`).
- Organize code by feature or domain: each feature folder contains `model`, `service`, `api`, and `tests` subfolders when appropriate.
- Use `.mli` files to define module contracts and hide implementation details.
- Prefer small modules with clear responsibilities; split large modules into submodules.
- Use `dune` library stanzas to expose libraries and `executable` stanzas for binaries.
- Explain how to run common commands: `opam install . --deps-only`, `dune build`, `dune runtest`, `dune exec ./bin/my_app.exe`.

## Module System and Signatures
- Design explicit signatures in `.mli` to document invariants and hide implementation.
- Use **functors** sparingly and only when you need to parameterize modules by behavior; prefer first-class modules for simpler cases.
- Keep module interfaces stable; bump versions and document breaking changes.
- Use `include` and `module type of` carefully to avoid leaking internals.

## Concurrency and Parallelism
- **Prefer Eio** for structured, effect-based concurrency on OCaml 5.4.0. Eio provides a modern, structured-concurrency model built on effect handlers that maps well to the multicore runtime and simplifies resource management and cancellation.
- Use Eio for I/O-bound services and when you want clear lifetimes for resources (scopes, fibers, cancellation).
- Apply **Pipeline / Railway oriented programming** (as described by Scott Wlaschin) for composing operations that can fail, especially in I/O and business-logic pipelines:
  - Model each step as a pure function returning `('a, 'err) result` and compose steps using `Result` combinators, `let*`/`let+` (ppx_let), or small pipeline helpers.
  - Use the **railway** pattern to separate success and failure flows clearly: keep success-path transformations simple and push error handling to the failure track where contextual enrichment and logging occur.
  - Prefer typed error variants and include contextual metadata so pipeline stages can add meaningful diagnostics without throwing exceptions.
  - Use small, focused combinators (`map`, `bind`, `map_error`, `both`) or lightweight helper modules to keep pipelines readable; avoid ad-hoc nesting of `match` expressions when a pipeline abstraction improves clarity.
  - Document pipeline boundaries and where side effects occur; keep side effects at the edges of the pipeline (I/O, DB, logging) and keep core pipeline steps pure for testability.
  - Use property-based tests or unit tests to validate pipeline invariants and error propagation.
  - Apply the railway approach judiciously: prefer it for multi-step validation, transformation, and I/O sequences; avoid over-abstracting trivial single-step functions.
- If you must interoperate with existing ecosystem code that expects cooperative libraries, consider using compatibility layers or adapters such as `lwt_eio`; document trade-offs and testing strategies.
- For CPU-bound parallelism, use **domains** and libraries like `domainslib`; be explicit about shared mutable state and synchronization to avoid data races.
- Be cautious mixing effect-based concurrency with libraries that are not effect-aware; prefer libraries that explicitly support effects or provide safe adapters.
- Prefer message-passing, immutable data, and well-defined boundaries between domains/fibers for safe concurrent designs.
- Document concurrency model choices in the README and module docs, including how cancellation, timeouts, and resource cleanup are handled.

## Error Handling and Validation
- Prefer typed error handling with `result` and `option` types; use `Rresult`, `result` combinators, or `ppx_let` for ergonomics.
- Use custom error variants to represent domain errors and include contextual information.
- Implement validation as pure functions returning `result` so they are easy to test.
- Use a global error-handling strategy at application boundaries (translate `exn` to structured errors only at top-level).

## Data Access Patterns
- Use database libraries appropriate to the project: **Caqti**, **PGOCaml**, or `postgresql` bindings for Postgres; `sqlite3` for embedded use.
- Keep SQL in separate modules or use query builders; prefer prepared statements and parameterized queries.
- Explain connection pooling and transaction boundaries; use `dune` and opam packages to pin DB client versions.
- Demonstrate migration strategies using tools like `migrate` or custom migration runners; include seeding examples for development.

## Web Frameworks and Authentication
- Recommend **Dream** or **Opium** for HTTP services; explain trade-offs and ecosystem maturity.
- Show how to implement authentication using JWT libraries (e.g., `ocaml-jwt`) and how to validate tokens securely.
- Explain session handling, CSRF protection, and secure cookie flags.
- Demonstrate role-based checks using typed claims and middleware that returns `result` or `option`.

## Logging and Monitoring
- Use **Logs** with a formatter like **Fmt** for structured, leveled logging.
- Explain logging levels and when to use each (debug, info, warn, error).
- Demonstrate integration with external telemetry systems via exporters or custom sinks.
- Show how to add correlation IDs to requests and propagate them through async code.

## Testing
- Include unit tests for critical paths using **Alcotest**.
- Use **QCheck** for property-based testing where appropriate.
- Keep tests deterministic and fast; mock external dependencies with small test doubles or in-memory implementations.
- Use `dune runtest` and show how to run a single test or test suite.
- Copy existing test naming and style from nearby files for consistency.
- Explain integration testing strategies for HTTP endpoints using `cohttp` test clients or `Dream` test helpers.

## Documentation
- Generate API docs with **odoc** and keep `README.md` and module-level docs up to date.
- Provide examples in `examples/` and include small runnable snippets demonstrating common flows.
- Document public types, invariants, and expected error cases in `.mli` comments.

## Interop and Native Extensions
- For C interop prefer `ctypes` for safer bindings or write C stubs when necessary; document memory ownership and safety.
- Explain how to build native extensions with `dune` and how to test them.
- Avoid `Obj.magic` and other unsafe operations unless absolutely necessary and clearly documented.

## Performance Optimization
- Profile with `perf`, `ocamlprof`, or `memtrace` before optimizing.
- Prefer tail-recursive functions for large lists and streams; use `List.fold_left`/`List.fold_right` appropriately.
- Use `Bigarray` for large binary buffers and avoid unnecessary allocations in hot paths.
- Consider `flambda` and `-O3` compiler flags for performance-sensitive builds.
- Explain trade-offs between immutability and controlled mutability for performance.

## Packaging and Deployment
- Use `opam` for packaging and dependency management; include an `opam` file with correct constraints.
- Use `dune` to produce native executables and explain `dune build --profile release`.
- Demonstrate containerization with Docker: build a small runtime image containing the native executable and required system libraries.
- Explain CI pipelines: run `opam` install, `dune build`, `dune runtest`, and `odoc` generation in CI.
- Show how to publish packages to the opam repository using `dune-release` and `opam-publish`.

## Security Best Practices
- Avoid embedding secrets in source; use environment variables or secret stores.
- Validate all external input and use typed encodings for untrusted data.
- Keep dependencies up to date and pin versions in CI to avoid supply-chain surprises.
- Use safe deserialization libraries and avoid `Marshal` for untrusted data.

## Migration and Compatibility
- When upgrading to OCaml 5.4.0, audit dependencies for multicore/effects compatibility.
- Run the test suite and static checks after each dependency upgrade.
- Document breaking changes and provide migration notes in `UPGRADE.md`.

## Tooling and Editor Integration
- Recommend **merlin**, **ocaml-lsp**, **dune**, **ocamlformat**, and **utop** for developer productivity.
- Provide editor configuration snippets for VS Code, Emacs, or Vim to enable merlin and ocaml-lsp features.
- Encourage using `dune` workspace and `dune` profiles for development and release.
