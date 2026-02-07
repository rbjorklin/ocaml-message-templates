(** Property-based tests for log filtering *)

open QCheck

(** Generate random log levels *)
let gen_level =
  Gen.oneof
    [ Gen.return Message_templates.Level.Verbose
    ; Gen.return Message_templates.Level.Debug
    ; Gen.return Message_templates.Level.Information
    ; Gen.return Message_templates.Level.Warning
    ; Gen.return Message_templates.Level.Error
    ; Gen.return Message_templates.Level.Fatal ]
;;

(** Property: Level can be compared *)
let prop_level_comparison =
  Test.make ~gen:gen_level ~name:"Levels can be compared"
    ~print:Message_templates.Level.to_string (fun level ->
      let open Message_templates.Level in
      level >= level && not (level < level) )
;;

(** Property: Any level filter is creatable *)
let prop_level_filter_safe =
  Test.make ~gen:gen_level ~name:"Any level can create a filter"
    ~print:Message_templates.Level.to_string (fun level ->
      try
        let _filter = Message_templates.Filter.by_level level in
        true
      with _ -> false )
;;

(** Property: Filter double negation is identity *)
let prop_double_negation =
  Test.make ~gen:gen_level ~name:"Filter double negation works"
    ~print:Message_templates.Level.to_string (fun level ->
      try
        let filter = Message_templates.Filter.by_level level in
        let double_not =
          Message_templates.Filter.not (Message_templates.Filter.not filter)
        in
        let event =
          Message_templates.Log_event.create ~level ~message_template:"test"
            ~rendered_message:"test" ~properties:[] ()
        in
        let result1 = Message_templates.Filter.applies filter event in
        let result2 = Message_templates.Filter.applies double_not event in
        result1 = result2
      with _ -> false )
;;

(** Property: Filter ALL with empty list *)
let prop_empty_all_filter =
  Test.make ~gen:gen_level ~name:"Empty ALL filter matches all"
    ~print:Message_templates.Level.to_string (fun level ->
      try
        let event =
          Message_templates.Log_event.create ~level ~message_template:"test"
            ~rendered_message:"test" ~properties:[] ()
        in
        let f = Message_templates.Filter.all [] in
        Message_templates.Filter.applies f event
      with _ -> false )
;;

(** All tests *)
let tests =
  [ prop_level_comparison
  ; prop_level_filter_safe
  ; prop_double_negation
  ; prop_empty_all_filter ]
;;

(** Run tests *)
let () =
  List.iter
    (fun t ->
      match Test.check_fun t with
      | QCheck.Success () -> Printf.printf "✓ %s\n" (Test.get_name t)
      | QCheck.Failure msg -> Printf.printf "✗ %s: %s\n" (Test.get_name t) msg
      | QCheck.Error (err, _) ->
          Printf.printf "✗ %s: %s\n" (Test.get_name t) err )
    tests
;;
