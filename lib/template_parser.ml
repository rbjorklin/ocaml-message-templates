(** Template parser using Angstrom *)

open Angstrom
open Types

(* Hole name: alphanumeric and underscores *)
let hole_name =
  take_while1 (function
    | '0' .. '9' | 'a' .. 'z' | 'A' .. 'Z' | '_' -> true
    | _ -> false )
;;

(* Operator: @ for structure, $ for stringify, or default *)
let operator =
  option Default (char '@' *> return Structure <|> char '$' *> return Stringify)
;;

(* Format specifier: : followed by format string *)
let format_spec = char ':' *> take_while1 (fun c -> c <> '}')

(* Alignment specifier: , followed by optional - and width *)
let alignment =
  char ',' *> option false (char '-' *> return true)
  >>= fun neg ->
  take_while1 (function
    | '0' .. '9' -> true
    | _ -> false )
  >>| fun n -> (neg, int_of_string n)
;;

(* Parse a hole: {operator name alignment format} *)
let hole =
  char '{' *> operator
  >>= fun op ->
  hole_name
  >>= fun name ->
  option None (alignment >>| fun a -> Some a)
  >>= fun align ->
  option None (format_spec >>| fun f -> Some f)
  >>= fun fmt ->
  char '}' *> return (Hole {name; operator= op; format= fmt; alignment= align})
;;

(* Escaped braces: {{ or }} *)
let escaped_brace =
  string "{{" *> return (Text "{") <|> string "}}" *> return (Text "}")
;;

(* Text content: any chars except '{' and '}' *)
let text = take_while1 (fun c -> c <> '{' && c <> '}') >>| fun s -> Text s

(* Template: sequence of text, escaped braces, and holes *)
let template = many (text <|> escaped_brace <|> hole)

(** Parse a template string into a list of parts *)
let parse_template str =
  match parse_string ~consume:All template str with
  | Ok parts -> Ok parts
  | Error msg -> Error msg
;;

(** Extract all hole names from a parsed template *)
let extract_holes parts =
  List.filter_map
    (function
      | Text _ -> None
      | Hole h -> Some h )
    parts
;;
