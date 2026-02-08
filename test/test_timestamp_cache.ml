(** Tests for timestamp cache module *)

open Alcotest
open Message_templates

let test_cache_hit () =
  (* Get timestamp twice in rapid succession - should be same cached value *)
  let entry1 = Timestamp_cache.get () in
  let entry2 = Timestamp_cache.get () in
  (* In same millisecond, should be identical *)
  check int64 "Same millisecond" entry1.epoch_ms entry2.epoch_ms;
  check string "Same RFC3339" entry1.rfc3339 entry2.rfc3339
;;

let test_cache_refresh () =
  (* Force cache invalidation and verify new entry created *)
  let entry1 = Timestamp_cache.get () in
  Timestamp_cache.invalidate ();
  let entry2 = Timestamp_cache.get () in
  (* Should be different cache instances *)
  check bool "Different after invalidate" false (entry1 == entry2)
;;

let test_ptime_consistency () =
  let entry = Timestamp_cache.get () in
  let expected_rfc3339 = Ptime.to_rfc3339 ~frac_s:3 entry.ptime in
  check string "RFC3339 matches Ptime" expected_rfc3339 entry.rfc3339
;;

let test_ptime_validity () =
  let entry = Timestamp_cache.get () in
  (* Ptime should not be epoch unless there was an error *)
  check bool "Ptime is valid" true
    (entry.ptime <> Ptime.epoch || entry.epoch_ms = 0L)
;;

let test_rfc3339_format () =
  let entry = Timestamp_cache.get () in
  (* RFC3339 should contain expected components *)
  check bool "Contains date separator" true (String.contains entry.rfc3339 '-');
  check bool "Contains time separator" true (String.contains entry.rfc3339 ':');
  check bool "Contains T separator" true (String.contains entry.rfc3339 'T')
;;

let test_disabled_caching () =
  (* Save current state *)
  let was_enabled = Timestamp_cache.is_enabled () in
  (* Disable caching *)
  Timestamp_cache.set_enabled false;
  (* Verify caching is now disabled *)
  check bool "Caching is disabled" false (Timestamp_cache.is_enabled ());
  (* Use the cache while disabled *)
  let _entry1 = Timestamp_cache.get () in
  (* Small delay *)
  Unix.sleepf 0.002;
  let _entry2 = Timestamp_cache.get () in
  (* Restore state *)
  Timestamp_cache.set_enabled was_enabled
;;

let test_enable_disable () =
  (* Test toggling the enabled flag *)
  Timestamp_cache.set_enabled true;
  check bool "Initially enabled" true (Timestamp_cache.is_enabled ());
  Timestamp_cache.set_enabled false;
  check bool "After disable" false (Timestamp_cache.is_enabled ());
  Timestamp_cache.set_enabled true;
  check bool "After re-enable" true (Timestamp_cache.is_enabled ())
;;

let test_get_ptime () =
  let ptime = Timestamp_cache.get_ptime () in
  (* Should return a valid Ptime.t *)
  let rfc3339 = Ptime.to_rfc3339 ptime in
  check bool "Ptime converts to string" true (String.length rfc3339 > 0)
;;

let test_get_rfc3339 () =
  let rfc3339 = Timestamp_cache.get_rfc3339 () in
  (* Should return a valid RFC3339 string *)
  check bool "RFC3339 has content" true (String.length rfc3339 > 10);
  (* Should follow RFC3339 format roughly *)
  check bool "Contains T" true (String.contains rfc3339 'T')
;;

let test_invalidate_effect () =
  (* Get a cached entry *)
  let entry1 = Timestamp_cache.get () in
  (* Invalidate and get again - should create new entry even in same ms *)
  Timestamp_cache.invalidate ();
  let entry2 = Timestamp_cache.get () in
  (* After invalidation, we should have a new entry object *)
  check bool "Different entry objects" false (entry1 == entry2)
;;

let () =
  run "Timestamp Cache Tests"
    [ ( "basic"
      , [ test_case "Cache hit in same millisecond" `Quick test_cache_hit
        ; test_case "Cache refresh after invalidate" `Quick test_cache_refresh
        ; test_case "Ptime/RFC3339 consistency" `Quick test_ptime_consistency
        ; test_case "Ptime validity" `Quick test_ptime_validity
        ; test_case "RFC3339 format" `Quick test_rfc3339_format ] )
    ; ( "configuration"
      , [ test_case "Enable/disable caching" `Quick test_enable_disable
        ; test_case "Disabled caching" `Quick test_disabled_caching ] )
    ; ( "convenience functions"
      , [ test_case "get_ptime returns valid time" `Quick test_get_ptime
        ; test_case "get_rfc3339 returns valid string" `Quick test_get_rfc3339
        ; test_case "invalidate creates new entry" `Quick test_invalidate_effect
        ] ) ]
;;
