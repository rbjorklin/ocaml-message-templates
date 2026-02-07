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

(** Property: Event level is stored *)
let prop_event_level_stored =
  Test.make ~gen:gen_level ~name:"Event level is stored"
    ~print:Message_templates.Level.to_string (fun level ->
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
  Test.make ~gen:Gen.unit ~name:"Event has RFC3339 timestamp"
    ~print:(fun () -> "()")
    (fun () ->
      try
        let event =
          Message_templates.Log_event.create
            ~level:Message_templates.Level.Information ~message_template:"test"
            ~rendered_message:"test" ~properties:[] ()
        in
        let ts = Message_templates.Log_event.get_timestamp event in
        String.contains ts 'T' && String.contains ts '-'
      with _ -> false )
;;

(** Property: Message template stored *)
let prop_message_template_stored =
  Test.make ~gen:Gen.string_printable ~name:"Message template is stored"
    ~print:Fun.id (fun template ->
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
  Test.make
    ~gen:(Gen.pair Gen.string_printable Gen.string_printable)
    ~name:"Properties are stored"
    ~print:(fun (k, v) -> Printf.sprintf "(%S, %S)" k v)
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

(** All tests *)
let tests =
  [ prop_event_level_stored
  ; prop_event_has_timestamp
  ; prop_message_template_stored
  ; prop_properties_stored ]
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
