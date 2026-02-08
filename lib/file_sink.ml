(** File sink - outputs log events to a file with optional rolling *)

type rolling_interval =
  | Infinite (* Never roll *)
  | Daily
  | Hourly

(** Internal state for file sink *)
type t =
  { base_path: string
  ; mutable current_path: string
  ; mutable oc: out_channel
  ; output_template: string
  ; rolling: rolling_interval
  ; mutable last_roll_time: Ptime.t }

(** Default file output template *)
let default_template = "{timestamp} [{level}] {message}"

(** Format a timestamp for display *)
let format_timestamp (tm : Ptime.t) = Ptime.to_rfc3339 tm

(** Get current time *)
let now () =
  match Ptime.of_float_s (Unix.gettimeofday ()) with
  | Some t -> t
  | None -> Ptime.epoch
;;

(** Get date string from Ptime for file naming *)
let format_date (tm : Ptime.t) =
  let epoch_sec = Ptime.to_float_s tm in
  let tm = Unix.gmtime epoch_sec in
  Printf.sprintf "%04d%02d%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
;;

(** Get hour string from Ptime for file naming *)
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

(** Roll to a new file *)
let roll t =
  close_out t.oc;
  let new_path = generate_path t.base_path t.rolling in
  t.current_path <- new_path;
  t.oc <- open_out_gen [Open_creat; Open_append; Open_text] 0o644 new_path;
  t.last_roll_time <- now ()
;;

(** Simple template formatting *)
let format_output t (event : Log_event.t) =
  let result = Runtime_helpers.format_sink_template t.output_template event in

  (* Append properties as JSON if any exist *)
  let props = Log_event.get_properties event in
  if props = [] then
    result
  else
    let json_props = `Assoc props in
    result ^ " " ^ Yojson.Safe.to_string json_props
;;

(** Emit a log event *)
let emit t event =
  (* Check if we need to roll *)
  let current_time = Log_event.get_timestamp event in
  if should_roll t current_time then
    roll t;

  let output_str = format_output t event in
  output_string t.oc output_str;
  output_char t.oc '\n'
;;

(** Flush output *)
let flush t = flush t.oc

(** Close the sink *)
let close t = close_out t.oc

(** Create a new file sink *)
let create ?(output_template = default_template) ?(rolling = Infinite) base_path
    =
  let initial_path = generate_path base_path rolling in
  let oc =
    open_out_gen [Open_creat; Open_append; Open_text] 0o644 initial_path
  in
  { base_path
  ; current_path= initial_path
  ; oc
  ; output_template
  ; rolling
  ; last_roll_time= now () }
;;
