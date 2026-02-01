(** Message Templates - Type-safe structured logging with PPX support

    A high-performance structured logging library for OCaml with compile-time
    template validation and zero-overhead when disabled.

    {2 Quick Start}

    {[
      (* Configure and set global logger *)
      let logger =
        Configuration.create ()
        |> Configuration.write_to_console ~colors:true ()
        |> Configuration.build
      in
      Log.set_logger logger;

      (* Log with structured data *)
      Log.information "User {username} logged in from {ip}"
        [("username", `String "alice"); ("ip", `String "192.168.1.1")]
    ]}

    {2 Features}

    - Type-safe message templates with compile-time validation
    - Structured JSON output (CLEF format)
    - Multiple sinks (console, file, JSON)
    - Log rotation (daily, hourly)
    - Contextual properties that flow across scopes
    - Correlation ID support for distributed tracing
    - Zero overhead when logging is disabled *)

(** {2 Core Types} *)

module Types = Types
module Level = Level
module Log_event = Log_event

(** {2 Template Parsing} *)

module Template_parser = Template_parser
module Runtime_helpers = Runtime_helpers

(** {2 Sinks} *)

module Sink = Sink
module Null_sink = Null_sink
module Console_sink = Console_sink
module File_sink = File_sink
module Json_sink = Json_sink
module Composite_sink = Composite_sink

(** {2 Configuration and Logging} *)

module Filter = Filter
module Configuration = Configuration
module Logger = Logger
module Log = Log
module Log_context = Log_context
