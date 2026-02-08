(** Console sink - outputs log events to stdout/stderr *)

type t =
  { output_template: string
  ; use_colors: bool
  ; stderr_threshold: Level.t
  ; output: out_channel }

(** Default console output template *)
let default_template = "{timestamp} [{level}] {message}"

(** Get color code for level *)
let level_color = function
  | Level.Verbose -> "\027[90m" (* Dark gray *)
  | Level.Debug -> "\027[36m" (* Cyan *)
  | Level.Information -> "\027[32m" (* Green *)
  | Level.Warning -> "\027[33m" (* Yellow *)
  | Level.Error -> "\027[31m" (* Red *)
  | Level.Fatal -> "\027[35m" (* Magenta *)
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
  let level_str = Level.to_short_string (Log_event.get_level event) in
  let result = Runtime_helpers.format_sink_template t.output_template event in

  (* Apply color to the level indicator *)
  if t.use_colors then
    let colored_level = colorize (Log_event.get_level event) true level_str in
    Str.global_replace (Str.regexp level_str) colored_level result
  else
    result
;;

(** Emit a log event *)
let emit t event =
  let output_str = format_output t event in
  let oc =
    if Level.(Log_event.get_level event >= t.stderr_threshold) then
      stderr
    else
      t.output
  in
  output_string oc output_str;
  output_char oc '\n';
  flush oc
;;

(** Flush output *)
let flush t = flush t.output

(** Close the sink *)
let close _t = ()

(** Create a new console sink *)
let create
    ?(output_template = default_template)
    ?(colors = false)
    ?(stderr_threshold = Level.Warning)
    () =
  {output_template; use_colors= colors; stderr_threshold; output= stdout}
;;
