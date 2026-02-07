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

(** Printer for log levels *)
let print_level = Message_templates.Level.to_string

(** Property: Level can be compared *)
let prop_level_comparison =
  Test.make ~count:100 ~name:"Levels can be compared"
    (make ~print:print_level gen_level) (fun level ->
      let open Message_templates.Level in
      level >= level && not (level < level) )
;;

(** Property: Any level filter is creatable *)
let prop_level_filter_safe =
  Test.make ~count:100 ~name:"Any level can create a filter"
    (make ~print:print_level gen_level) (fun level ->
      try
        let _filter = Message_templates.Filter.level_filter level in
        true
      with _ -> false )
;;

(** Property: Filter double negation is identity *)
let prop_double_negation =
  Test.make ~count:100 ~name:"Filter double negation works"
    (make ~print:print_level gen_level) (fun level ->
      try
        let filter = Message_templates.Filter.level_filter level in
        let double_not =
          Message_templates.Filter.not_filter
            (Message_templates.Filter.not_filter filter)
        in
        let event =
          Message_templates.Log_event.create ~level ~message_template:"test"
            ~rendered_message:"test" ~properties:[] ()
        in
        let result1 = filter event in
        let result2 = double_not event in
        result1 = result2
      with _ -> false )
;;

(** Property: Filter ALL with empty list *)
let prop_empty_all_filter =
  Test.make ~count:100 ~name:"Empty ALL filter matches all"
    (make ~print:print_level gen_level) (fun level ->
      try
        let event =
          Message_templates.Log_event.create ~level ~message_template:"test"
            ~rendered_message:"test" ~properties:[] ()
        in
        let f = Message_templates.Filter.all [] in
        f event
      with _ -> false )
;;

(** Helper to run a single test *)
let run_test name test =
  try
    Test.check_exn test;
    Printf.printf "✓ %s\n" name
  with
  | Test.Test_fail (_, msgs) ->
      Printf.printf "✗ %s: %s\n" name (String.concat ", " msgs)
  | Test.Test_error (_, err, _, _) -> Printf.printf "✗ %s: %s\n" name err
;;

(** Run tests *)
let () =
  run_test "Levels can be compared" prop_level_comparison;
  run_test "Any level can create a filter" prop_level_filter_safe;
  run_test "Filter double negation works" prop_double_negation;
  run_test "Empty ALL filter matches all" prop_empty_all_filter
;;
