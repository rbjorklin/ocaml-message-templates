(** Lwt console sink - async console output *)

open Message_templates

(** Console sink type *)
type t =
  { output_template: string
  ; use_colors: bool
  ; stderr_threshold: Level.t }

(** Default console output template *)
let default_template = "[{timestamp} {level}] {message}"

(** Format a timestamp for display *)
let format_timestamp (tm : Ptime.t) = Ptime.to_rfc3339 tm

(** Get color code for level *)
let level_color = function
  | Level.Verbose -> "\027[90m"
  | Level.Debug -> "\027[36m"
  | Level.Information -> "\027[32m"
  | Level.Warning -> "\027[33m"
  | Level.Error -> "\027[31m"
  | Level.Fatal -> "\027[35m"
;;

(** Reset color *)
let reset_color = "\027[0m"

(** Apply color to string if enabled *)
let colorize level use_colors str =
  if use_colors then
    level_color level ^ str ^ reset_color
  else
    str
;;

(** Simple template formatting *)
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
  if t.use_colors then
    let colored_level = colorize (Log_event.get_level event) true level_str in
    Str.global_replace (Str.regexp level_str) colored_level result
  else
    result
;;

(** Emit a log event *)
let emit t event =
  let output_str = format_output t event in
  if Level.(Log_event.get_level event >= t.stderr_threshold) then
    Lwt_io.write_line Lwt_io.stderr output_str
  else
    Lwt_io.write_line Lwt_io.stdout output_str
;;

(** Flush output *)
let flush _t = Lwt_io.flush Lwt_io.stdout

(** Close the sink *)
let close _t = Lwt.return ()

(** Create a new Lwt console sink *)
let create
    ?(output_template = default_template)
    ?(colors = false)
    ?(stderr_threshold = Level.Warning)
    () =
  {output_template; use_colors= colors; stderr_threshold}
;;
