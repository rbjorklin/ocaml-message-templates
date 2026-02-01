(** Core types for Message Templates *)

type operator =
  | Default
  | Structure
  | Stringify

type hole =
  { name: string
  ; operator: operator
  ; format: string option
  ; alignment: (bool * int) option (* (is_negative, width) *) }

type template_part =
  | Text of string
  | Hole of hole

type parsed_template = template_part list

(** Convert operator to string for debugging *)
let string_of_operator = function
  | Default -> ""
  | Structure -> "@"
  | Stringify -> "$"
;;

(** Convert a hole to string representation *)
let string_of_hole h =
  let op = string_of_operator h.operator in
  let align =
    match h.alignment with
    | None -> ""
    | Some (neg, width) ->
        let sign =
          if neg then
            "-"
          else
            ""
        in
        Printf.sprintf ",%s%d" sign width
  in
  let fmt =
    match h.format with
    | None -> ""
    | Some f -> ":" ^ f
  in
  Printf.sprintf "{%s%s%s%s}" op h.name align fmt
;;

(** Reconstruct a template from parsed parts *)
let reconstruct_template parts =
  let buf = Buffer.create 256 in
  List.iter
    (function
      | Text s -> Buffer.add_string buf s
      | Hole h -> Buffer.add_string buf (string_of_hole h) )
    parts;
  Buffer.contents buf
;;
