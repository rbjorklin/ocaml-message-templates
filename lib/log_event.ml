(** Log event type - immutable record representing a single log entry *)

type t =
  { timestamp: Ptime.t (* Event timestamp *)
  ; level: Level.t (* Severity level *)
  ; message_template: string (* Original template *)
  ; rendered_message: string (* Formatted message *)
  ; properties: (string * Yojson.Safe.t) list (* Structured properties *)
  ; exception_info: exn option (* Optional exception *) }

(** Create a new log event *)
let create
    ?timestamp
    ?exception_info
    ~level
    ~message_template
    ~rendered_message
    ~properties
    () =
  let ts =
    match timestamp with
    | Some t -> t
    | None -> (
        (* Get current time from Unix timestamp *)
        let now = Unix.gettimeofday () in
        match Ptime.of_float_s now with
        | Some t -> t
        | None -> Ptime.epoch )
  in
  { timestamp= ts
  ; level
  ; message_template
  ; rendered_message
  ; properties
  ; exception_info }
;;

(** Convert log event to Yojson for output *)
let to_yojson event =
  let base_props =
    [ ("@t", `String (Ptime.to_rfc3339 event.timestamp))
    ; ("@mt", `String event.message_template)
    ; ("@l", `String (Level.to_string event.level))
    ; ("@m", `String event.rendered_message) ]
  in
  let props = base_props @ event.properties in
  `Assoc props
;;

(** Get the timestamp *)
let get_timestamp event = event.timestamp

(** Get the level *)
let get_level event = event.level

(** Get the message template *)
let get_message_template event = event.message_template

(** Get the rendered message *)
let get_rendered_message event = event.rendered_message

(** Get the properties *)
let get_properties event = event.properties

(** Get exception info if present *)
let get_exception event = event.exception_info
