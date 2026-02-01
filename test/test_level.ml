(** Tests for Level module *)

open Alcotest
open Message_templates

let test_level_ordering () =
  (* Test that levels compare correctly *)
  check bool "Verbose < Debug" true (Level.compare Level.Verbose Level.Debug < 0);
  check bool "Debug < Information" true (Level.compare Level.Debug Level.Information < 0);
  check bool "Information < Warning" true (Level.compare Level.Information Level.Warning < 0);
  check bool "Warning < Error" true (Level.compare Level.Warning Level.Error < 0);
  check bool "Error < Fatal" true (Level.compare Level.Error Level.Fatal < 0);
  check bool "Verbose = Verbose" true (Level.compare Level.Verbose Level.Verbose = 0)

let test_level_to_int () =
  check int "Verbose = 0" 0 (Level.to_int Level.Verbose);
  check int "Debug = 1" 1 (Level.to_int Level.Debug);
  check int "Information = 2" 2 (Level.to_int Level.Information);
  check int "Warning = 3" 3 (Level.to_int Level.Warning);
  check int "Error = 4" 4 (Level.to_int Level.Error);
  check int "Fatal = 5" 5 (Level.to_int Level.Fatal)

let test_level_of_string () =
  let check_level_opt name expected actual =
    match expected, actual with
    | Some e, Some a -> check bool name (e = a) true
    | None, None -> check bool name true true
    | Some _, None -> check bool name false true
    | None, Some _ -> check bool name false true
  in
  check_level_opt "Verbose" (Some Level.Verbose) (Level.of_string "Verbose");
  check_level_opt "verbose" (Some Level.Verbose) (Level.of_string "verbose");
  check_level_opt "VRB" (Some Level.Verbose) (Level.of_string "VRB");
  check_level_opt "Debug" (Some Level.Debug) (Level.of_string "Debug");
  check_level_opt "debug" (Some Level.Debug) (Level.of_string "debug");
  check_level_opt "DBG" (Some Level.Debug) (Level.of_string "DBG");
  check_level_opt "Information" (Some Level.Information) (Level.of_string "Information");
  check_level_opt "INF" (Some Level.Information) (Level.of_string "INF");
  check_level_opt "Warning" (Some Level.Warning) (Level.of_string "Warning");
  check_level_opt "WRN" (Some Level.Warning) (Level.of_string "WRN");
  check_level_opt "Error" (Some Level.Error) (Level.of_string "Error");
  check_level_opt "ERR" (Some Level.Error) (Level.of_string "ERR");
  check_level_opt "Fatal" (Some Level.Fatal) (Level.of_string "Fatal");
  check_level_opt "FTL" (Some Level.Fatal) (Level.of_string "FTL");
  check_level_opt "Unknown" None (Level.of_string "Unknown")

let test_level_to_string () =
  check string "Verbose" "Verbose" (Level.to_string Level.Verbose);
  check string "Debug" "Debug" (Level.to_string Level.Debug);
  check string "Information" "Information" (Level.to_string Level.Information);
  check string "Warning" "Warning" (Level.to_string Level.Warning);
  check string "Error" "Error" (Level.to_string Level.Error);
  check string "Fatal" "Fatal" (Level.to_string Level.Fatal)

let test_level_to_short_string () =
  check string "Verbose" "VRB" (Level.to_short_string Level.Verbose);
  check string "Debug" "DBG" (Level.to_short_string Level.Debug);
  check string "Information" "INF" (Level.to_short_string Level.Information);
  check string "Warning" "WRN" (Level.to_short_string Level.Warning);
  check string "Error" "ERR" (Level.to_short_string Level.Error);
  check string "Fatal" "FTL" (Level.to_short_string Level.Fatal)

let test_level_comparison_operators () =
  (* Test >= operator *)
  check bool "Fatal >= Error" true (Level.Fatal >= Level.Error);
  check bool "Error >= Error" true (Level.Error >= Level.Error);
  check bool "Debug >= Error" false (Level.Debug >= Level.Error);
  
  (* Test < operator *)
  check bool "Debug < Error" true (Level.Debug < Level.Error);
  check bool "Error < Error" false (Level.Error < Level.Error);
  check bool "Fatal < Error" false (Level.Fatal < Level.Error)

let () =
  run "Level Tests" [
    "ordering", [
      test_case "Level ordering" `Quick test_level_ordering;
      test_case "Level to int" `Quick test_level_to_int;
    ];
    "conversion", [
      test_case "Level of string" `Quick test_level_of_string;
      test_case "Level to string" `Quick test_level_to_string;
      test_case "Level to short string" `Quick test_level_to_short_string;
    ];
    "comparison", [
      test_case "Level comparison operators" `Quick test_level_comparison_operators;
    ];
  ]
