(** Log event type - immutable record representing a single log entry *)

type t =
  { timestamp: Ptime.t
  ; level: Level.t
  ; message_template: string
  ; rendered_message: string
  ; properties: (string * Yojson.Safe.t) list
  ; exception_info: exn option
  ; correlation_id: string option }

(** Create a new log event *)
let create
    ?timestamp
    ?exception_info
    ?correlation_id
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
  ; exception_info
  ; correlation_id }
;;

(** Append an escaped string directly to a buffer for JSON output. Avoids
    intermediate buffer allocation compared to escape_json_string. *)
let append_escaped_string buf s =
  let len = String.length s in
  for i = 0 to len - 1 do
    match s.[i] with
    | '"' -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\b' -> Buffer.add_string buf "\\b"
    | '\012' -> Buffer.add_string buf "\\f"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\r' -> Buffer.add_string buf "\\r"
    | '\t' -> Buffer.add_string buf "\\t"
    | c when Char.code c < 0x20 -> Printf.bprintf buf "\\u%04x" (Char.code c)
    | c -> Buffer.add_char buf c
  done
;;

(** Escape a string for JSON output (kept for backward compatibility) *)
let escape_json_string s =
  let buf = Buffer.create (String.length s + 10) in
  append_escaped_string buf s;
  Buffer.contents buf
;;

(** Append a JSON value to a buffer *)
let rec append_json_value buf = function
  | `Null -> Buffer.add_string buf "null"
  | `Bool true -> Buffer.add_string buf "true"
  | `Bool false -> Buffer.add_string buf "false"
  | `Int i -> Buffer.add_string buf (string_of_int i)
  | `Float f -> Printf.bprintf buf "%.17g" f
  | `String s ->
      Buffer.add_char buf '"';
      append_escaped_string buf s;
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
            append_escaped_string buf k;
            Buffer.add_string buf "\":";
            append_json_value buf v
        | (k, v) :: rest ->
            Buffer.add_char buf '"';
            append_escaped_string buf k;
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
  append_escaped_string buf key;
  Buffer.add_string buf "\":";
  append_json_value buf value
;;

(** Convert log event to JSON string. This builds the JSON string directly using
    a Buffer, avoiding intermediate Yojson.Safe.t structures and allocations. *)
let to_json_string event =
  (* Pre-size buffer based on typical event size *)
  let buf = Buffer.create 256 in
  Buffer.add_char buf '{';

  (* @t - timestamp *)
  Buffer.add_string buf "\"@t\":\"";
  Buffer.add_string buf (Ptime.to_rfc3339 event.timestamp);
  Buffer.add_string buf "\",";

  (* @mt - message template *)
  Buffer.add_string buf "\"@mt\":\"";
  append_escaped_string buf event.message_template;
  Buffer.add_string buf "\",";

  (* @l - level *)
  Buffer.add_string buf "\"@l\":\"";
  Buffer.add_string buf (Level.to_string event.level);
  Buffer.add_string buf "\",";

  (* @m - rendered message *)
  Buffer.add_string buf "\"@m\":\"";
  append_escaped_string buf event.rendered_message;
  Buffer.add_char buf '"';

  (* Correlation ID if present *)
  ( match event.correlation_id with
  | None -> ()
  | Some id ->
      Buffer.add_string buf ",\"CorrelationId\":\"";
      append_escaped_string buf id;
      Buffer.add_char buf '"' );

  (* Additional properties *)
  List.iter
    (fun prop -> Buffer.add_char buf ','; append_property buf prop)
    event.properties;

  Buffer.add_char buf '}';
  Buffer.contents buf
;;

(** Field accessors *)
let get_timestamp event = event.timestamp

let get_level event = event.level

let get_message_template event = event.message_template

let get_rendered_message event = event.rendered_message

let get_properties event = event.properties

let get_exception event = event.exception_info

let get_correlation_id event = event.correlation_id
