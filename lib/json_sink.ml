(** JSON sink - outputs log events as pure CLEF/JSON format *)

type t = {oc: out_channel}

(** Emit a log event as JSON *)
let emit t event =
  let json_str = Log_event.to_json_string event in
  output_string t.oc json_str;
  output_char t.oc '\n'
;;

(** Flush output *)
let flush t = flush t.oc

(** Close the sink *)
let close t = close_out t.oc

(** Create a new JSON sink *)
let create path =
  let oc = open_out_gen [Open_creat; Open_append; Open_text] 0o644 path in
  {oc}
;;

(** Create a JSON sink from an existing output channel *)
let of_out_channel oc = {oc}
