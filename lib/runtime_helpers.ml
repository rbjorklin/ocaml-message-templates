(** Runtime helpers for message templates *)

let rec to_string : 'a. 'a -> string = fun v ->
  let repr = Obj.repr v in
  if Obj.is_int repr then
    string_of_int (Obj.obj repr)
  else if Obj.is_block repr then
    let tag = Obj.tag repr in
    if tag = 252 then (* string tag *)
      (Obj.obj repr : string)
    else if tag = 253 then (* float tag *)
      string_of_float (Obj.obj repr)
    else if tag = 254 then (* float array tag *)
      "<float array>"
    else if tag = 255 then (* custom tag *)
      "<custom>"
    else
      (* Regular block - could be a list, tuple, etc. *)
      let size = Obj.size repr in
      if size = 0 then
        "()"
      else
        let elems = Array.init size (fun i -> to_string (Obj.field repr i)) in
        "[" ^ String.concat "; " (Array.to_list elems) ^ "]"
  else
    "<unknown>"
