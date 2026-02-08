(lang dune 3.21)
(using mdx 0.2)
(name message-templates)
(version 0.1.0)
(generate_opam_files true)

(source
 (github ocaml-community/message-templates))

(authors "OCaml Community")

(maintainers "OCaml Community")

(license MIT)

(documentation https://ocaml-community.github.io/message-templates)

(package
 (name message-templates)
 (synopsis "Type-safe Message Templates for OCaml with PPX")
 (description "A PPX-based implementation of Message Templates for OCaml that provides type-safe, compile-time validated templates with automatic scope capture and both string and JSON output.")
  (depends
    (ocaml (>= 5.4.0))
    (dune (>= 3.0))
    (ppxlib (>= 0.35.0))
    (angstrom (>= 0.15.0))
    (yojson (>= 2.0.0))
    (ptime (>= 1.0))
     (alcotest :with-test)
     (qcheck :with-test)
     (mdx :with-test)
     (core_bench :with-dev)
     (ppx_bench :with-dev)))

(package
 (name message-templates-ppx)
 (synopsis "PPX for Message Templates")
 (description "The PPX rewriter for message-templates")
 (depends
  (ocaml (>= 5.4.0))
  (dune (>= 3.0))
  (ppxlib (>= 0.35.0))
  (angstrom (>= 0.15.0))
  (message-templates (= :version))))

(package
 (name message-templates-lwt)
 (synopsis "Lwt async support for Message Templates")
 (description "Async logging support using Lwt for the message-templates library")
 (depends
  (ocaml (>= 5.4.0))
  (dune (>= 3.0))
  (message-templates (= :version))
  (lwt (>= 5.6))
  (lwt-unix (>= 5.6))
  (yojson (>= 2.0.0))
  (ptime (>= 1.0))
  (alcotest :with-test)))

(package
 (name message-templates-eio)
 (synopsis "Eio async support for Message Templates")
 (description "Async logging support using Eio for the message-templates library")
 (depends
  (ocaml (>= 5.4.0))
  (dune (>= 3.0))
  (message-templates (= :version))
  (eio (>= 1.0))
  (eio_main (>= 1.0))
  (yojson (>= 2.0.0))
  (ptime (>= 1.0))
  (alcotest :with-test)))
