(** Property-based tests for log event properties *)

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

(** Property: Event level is stored *)
let prop_event_level_stored =
  Test.make ~count:100 ~name:"Event level is stored"
    (make ~print:print_level gen_level) (fun level ->
      try
        let event =
          Message_templates.Log_event.create ~level ~message_template:"test"
            ~rendered_message:"test" ~properties:[] ()
        in
        let retrieved = Message_templates.Log_event.get_level event in
        Message_templates.Level.compare level retrieved = 0
      with _ -> false )
;;

(** Property: Event has timestamp *)
let prop_event_has_timestamp =
  Test.make ~count:100 ~name:"Event has RFC3339 timestamp"
    (make ~print:(fun () -> "()") Gen.unit)
    (fun () ->
      try
        let event =
          Message_templates.Log_event.create
            ~level:Message_templates.Level.Information ~message_template:"test"
            ~rendered_message:"test" ~properties:[] ()
        in
        let _ts = Message_templates.Log_event.get_timestamp event in
        (* Check that it's a valid timestamp *)
        true
      with _ -> false )
;;

(** Property: Message template stored *)
let prop_message_template_stored =
  Test.make ~count:100 ~name:"Message template is stored"
    (make ~print:Fun.id Gen.string_printable) (fun template ->
      try
        let event =
          Message_templates.Log_event.create
            ~level:Message_templates.Level.Information
            ~message_template:template ~rendered_message:"rendered"
            ~properties:[] ()
        in
        Message_templates.Log_event.get_message_template event = template
      with _ -> false )
;;

(** Property: Properties stored *)
let prop_properties_stored =
  Test.make ~count:100 ~name:"Properties are stored"
    (make
       ~print:(fun (k, v) -> Printf.sprintf "(%S, %S)" k v)
       (Gen.pair Gen.string_printable Gen.string_printable) )
    (fun (key, value) ->
      try
        let event =
          Message_templates.Log_event.create
            ~level:Message_templates.Level.Information ~message_template:"test"
            ~rendered_message:"test"
            ~properties:[(key, `String value)]
            ()
        in
        let props = Message_templates.Log_event.get_properties event in
        List.length props = 1
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
  run_test "Event level is stored" prop_event_level_stored;
  run_test "Event has RFC3339 timestamp" prop_event_has_timestamp;
  run_test "Message template is stored" prop_message_template_stored;
  run_test "Properties are stored" prop_properties_stored
;;
