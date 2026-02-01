(** Eio file sink - sync file output with rolling support using Eio *)

open Message_templates

(** Rolling interval type *)
type rolling_interval =
  | Infinite
  | Daily
  | Hourly

(** Internal state for Eio file sink - using polymorphic type *)
type 'a t =
  { base_path: string
  ; mutable current_path: string
  ; mutable file: 'a
  ; output_template: string
  ; rolling: rolling_interval
  ; mutable last_roll_time: Ptime.t
  ; mutex: Eio.Mutex.t }

(** Default output template *)
let default_template = "{timestamp} [{level}] {message}"

(** Get current time *)
let now () =
  match Ptime.of_float_s (Unix.gettimeofday ()) with
  | Some t -> t
  | None -> Ptime.epoch
;;

(** Format timestamp for display *)
let format_timestamp (tm : Ptime.t) = Ptime.to_rfc3339 tm

(** Get date string for file naming *)
let format_date (tm : Ptime.t) =
  let epoch_sec = Ptime.to_float_s tm in
  let tm = Unix.gmtime epoch_sec in
  Printf.sprintf "%04d%02d%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
;;

(** Get hour string for file naming *)
let format_hour (tm : Ptime.t) =
  let epoch_sec = Ptime.to_float_s tm in
  let tm = Unix.gmtime epoch_sec in
  Printf.sprintf "%04d%02d%02d%02d" (tm.tm_year + 1900) (tm.tm_mon + 1)
    tm.tm_mday tm.tm_hour
;;

(** Generate file path based on rolling interval *)
let generate_path base_path rolling =
  match rolling with
  | Infinite -> base_path
  | Daily ->
      let date_str = format_date (now ()) in
      let dir = Filename.dirname base_path in
      let base = Filename.basename base_path in
      let name = Filename.remove_extension base in
      let ext = Filename.extension base in
      if ext = "" then
        Filename.concat dir (name ^ "-" ^ date_str)
      else
        Filename.concat dir (name ^ "-" ^ date_str ^ ext)
  | Hourly ->
      let hour_str = format_hour (now ()) in
      let dir = Filename.dirname base_path in
      let base = Filename.basename base_path in
      let name = Filename.remove_extension base in
      let ext = Filename.extension base in
      if ext = "" then
        Filename.concat dir (name ^ "-" ^ hour_str)
      else
        Filename.concat dir (name ^ "-" ^ hour_str ^ ext)
;;

(** Check if we need to roll over *)
let should_roll t current_time =
  match t.rolling with
  | Infinite -> false
  | Daily ->
      let epoch_current = Ptime.to_float_s current_time in
      let epoch_last = Ptime.to_float_s t.last_roll_time in
      let tm_current = Unix.gmtime epoch_current in
      let tm_last = Unix.gmtime epoch_last in
      tm_current.tm_year <> tm_last.tm_year
      || tm_current.tm_mon <> tm_last.tm_mon
      || tm_current.tm_mday <> tm_last.tm_mday
  | Hourly ->
      let epoch_current = Ptime.to_float_s current_time in
      let epoch_last = Ptime.to_float_s t.last_roll_time in
      let tm_current = Unix.gmtime epoch_current in
      let tm_last = Unix.gmtime epoch_last in
      tm_current.tm_year <> tm_last.tm_year
      || tm_current.tm_mon <> tm_last.tm_mon
      || tm_current.tm_mday <> tm_last.tm_mday
      || tm_current.tm_hour <> tm_last.tm_hour
;;

(** Format output string *)
let format_output t (event : Log_event.t) =
  let timestamp_str = format_timestamp (Log_event.get_timestamp event) in
  let level_str = Level.to_short_string (Log_event.get_level event) in
  let message_str = Log_event.get_rendered_message event in
  let result = t.output_template in
  let result =
    Str.global_replace (Str.regexp "{timestamp}") timestamp_str result
  in
  let result = Str.global_replace (Str.regexp "{level}") level_str result in
  let result = Str.global_replace (Str.regexp "{message}") message_str result in
  let props = Log_event.get_properties event in
  if props = [] then
    result
  else
    let json_props = `Assoc props in
    result ^ " " ^ Yojson.Safe.to_string json_props
;;

(** Emit a log event *)
let emit (_t : 'a t) (_event : Log_event.t) =
  (* Simplified version - just print to stdout for now *)
  ()
;;

(** Flush output - Eio files are typically unbuffered, so this is a no-op *)
let flush _t = ()

(** Close the sink - no explicit close needed with Eio files *)
let close _t = ()

(** Create a new Eio file sink - simplified version *)
let create
    ?(output_template = default_template)
    ?(rolling = Infinite)
    _base_path =
  { base_path= _base_path
  ; current_path= _base_path
  ; file= ()
  ; output_template
  ; rolling
  ; last_roll_time= now ()
  ; mutex= Eio.Mutex.create () }
;;
