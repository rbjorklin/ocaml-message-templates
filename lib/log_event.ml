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

(** Escape a string for JSON output *)
let escape_json_string s =
  let buf = Buffer.create (String.length s + 10) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\b' -> Buffer.add_string buf "\\b"
      | '\012' -> Buffer.add_string buf "\\f"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\r' -> Buffer.add_string buf "\\r"
      | '\t' -> Buffer.add_string buf "\\t"
      | c when Char.code c < 0x20 ->
          Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char buf c )
    s;
  Buffer.contents buf
;;

(** Append a JSON value to a buffer *)
let rec append_json_value buf = function
  | `Null -> Buffer.add_string buf "null"
  | `Bool true -> Buffer.add_string buf "true"
  | `Bool false -> Buffer.add_string buf "false"
  | `Int i -> Buffer.add_string buf (string_of_int i)
  | `Float f -> Buffer.add_string buf (Printf.sprintf "%.17g" f)
  | `String s ->
      Buffer.add_char buf '"';
      Buffer.add_string buf (escape_json_string s);
      Buffer.add_char buf '"'
  | `Intlit s -> Buffer.add_string buf s
  | `List lst ->
      Buffer.add_char buf '[';
      let rec add_elems = function
        | [] -> ()
        | [x] -> append_json_value buf x
        | x :: xs ->
            append_json_value buf x; Buffer.add_char buf ','; add_elems xs
      in
      add_elems lst; Buffer.add_char buf ']'
  | `Assoc fields ->
      Buffer.add_char buf '{';
      let rec add_fields = function
        | [] -> ()
        | [(k, v)] ->
            Buffer.add_char buf '"';
            Buffer.add_string buf (escape_json_string k);
            Buffer.add_string buf "\":";
            append_json_value buf v
        | (k, v) :: rest ->
            Buffer.add_char buf '"';
            Buffer.add_string buf (escape_json_string k);
            Buffer.add_string buf "\":";
            append_json_value buf v;
            Buffer.add_char buf ',';
            add_fields rest
      in
      add_fields fields; Buffer.add_char buf '}'
  | `Tuple lst -> append_json_value buf (`List lst)
;;

(** Convert a property to JSON and append to buffer *)
let append_property buf (key, value) =
  Buffer.add_char buf '"';
  Buffer.add_string buf (escape_json_string key);
  Buffer.add_string buf "\":";
  append_json_value buf value
;;

(** Optimized direct JSON string generation. This builds the JSON string
    directly using a Buffer, avoiding intermediate Yojson.Safe.t structures and
    allocations. *)
let to_json_string event =
  let buf = Buffer.create 512 in
  Buffer.add_char buf '{';

  (* @t - timestamp *)
  Buffer.add_string buf "\"@t\":\"";
  Buffer.add_string buf (Ptime.to_rfc3339 event.timestamp);
  Buffer.add_string buf "\",";

  (* @mt - message template *)
  Buffer.add_string buf "\"@mt\":\"";
  Buffer.add_string buf (escape_json_string event.message_template);
  Buffer.add_string buf "\",";

  (* @l - level *)
  Buffer.add_string buf "\"@l\":\"";
  Buffer.add_string buf (Level.to_string event.level);
  Buffer.add_string buf "\",";

  (* @m - rendered message *)
  Buffer.add_string buf "\"@m\":\"";
  Buffer.add_string buf (escape_json_string event.rendered_message);
  Buffer.add_char buf '"';

  (* Additional properties *)
  List.iter
    (fun prop -> Buffer.add_char buf ','; append_property buf prop)
    event.properties;

  Buffer.add_char buf '}';
  Buffer.contents buf
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
