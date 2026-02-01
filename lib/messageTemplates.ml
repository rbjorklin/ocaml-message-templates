(** Message Templates - Type-safe templating with PPX support *)

module Types = Types
module Template_parser = Template_parser
module Runtime_helpers = Runtime_helpers
module Level = Level
module Log_event = Log_event
module Sink = Sink
module Console_sink = Console_sink
module File_sink = File_sink
module Null_sink = Null_sink
module Composite_sink = Composite_sink
module Logger = Logger
module Filter = Filter
module Configuration = Configuration
module Log = Log
module Log_context = Log_context

(** The PPX rewriter will generate code that returns a tuple of (string, Yojson.Safe.t)
    representing the formatted message and structured JSON output. *)
