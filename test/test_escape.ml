(** Test escaped braces parsing *)

open Message_templates

let () =
  let template = "{{braces}}" in
  match Template_parser.parse_template template with
  | Ok parts ->
      Printf.printf "Parsed %d parts:\n" (List.length parts);
      List.iteri (fun i part ->
        match part with
        | Types.Text s -> Printf.printf "  Part %d: Text %S\n" i s
        | Types.Hole h -> Printf.printf "  Part %d: Hole %s\n" i h.name
      ) parts;
      let reconstructed = Types.reconstruct_template parts in
      Printf.printf "Reconstructed: %S\n" reconstructed
  | Error msg -> Printf.printf "Error: %s\n" msg
