(** Common patterns and utilities for async logging *)

(** Composite sink pattern *)
module Async_sink = struct
  let composite_emits emits event =
    List.map (fun emit -> emit event) emits
end

(** Logger implementation pattern *)
module Async_logger = struct
  let check_enabled _logger _level =
    true

  let apply_enrichers _logger event =
    event

  let passes_filters _logger _event =
    true
end

(** Utilities *)
module Async_utils = struct
  let make_composite ops event =
    List.iter (fun op -> op event) ops

  let type_check () =
    ()
end
