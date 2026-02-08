# Plan 8: Add Configuration Validation

## Status
**Priority:** LOW  
**Estimated Effort:** 3-4 hours  
**Risk Level:** Low (quality of life improvement)

## Problem Statement

The Configuration builder allows creating invalid or contradictory configurations:

```ocaml
(* This compiles but may not work as expected *)
let config =
  Configuration.create ()
  |> Configuration.minimum_level Level.Error
  |> Configuration.filter_by (Filter.level_filter Level.Debug)  
  (* Filter says Debug+, but minimum_level says Error+ - confusing! *)
```

### Issues

1. **No Validation**: Can create configurations that silently ignore events
2. **Order-Dependent Behavior**: Order of operations affects result, but this isn't documented
3. **No Warnings**: Duplicate or conflicting settings aren't flagged
4. **No Helpful Errors**: Configuration errors only appear at runtime

## Solution

Add a validation phase to `create_logger` that:
1. Detects common misconfigurations
2. Warns about suspicious patterns
3. Provides helpful error messages
4. Documents ordering requirements

## Implementation Steps

### Step 1: Define Validation Types

**File:** `lib/configuration.mli` (additions)

```ocaml
(** Validation result *)
type validation_result =
  | Valid
  | Warning of string list
  | Error of string list

(** Validation options *)
type validation_options =
  { check_redundant_filters: bool
  ; check_level_consistency: bool
  ; check_sink_configs: bool
  ; warn_no_sinks: bool
  ; warn_high_verbosity: bool }

val default_validation_options : validation_options

(** Validate a configuration before building logger *)
val validate : ?options:validation_options -> t -> validation_result

(** Create logger with validation (raises on error) *)
val create_logger_validated : ?options:validation_options -> t -> Logger.t
```

### Step 2: Implement Validation Logic

**File:** `lib/configuration.ml` (additions)

```ocaml
type validation_result =
  | Valid
  | Warning of string list
  | Error of string list

type validation_options =
  { check_redundant_filters: bool
  ; check_level_consistency: bool
  ; check_sink_configs: bool
  ; warn_no_sinks: bool
  ; warn_high_verbosity: bool }

let default_validation_options =
  { check_redundant_filters= true
  ; check_level_consistency= true
  ; check_sink_configs= true
  ; warn_no_sinks= true
  ; warn_high_verbosity= true }

let validate ?(options=default_validation_options) config =
  let warnings = ref [] in
  let errors = ref [] in
  
  (* Check 1: No sinks configured *)
  if options.warn_no_sinks && config.sinks = [] then
    warnings := "No sinks configured - logger will discard all events" :: !warnings;
  
  (* Check 2: Minimum level vs filter inconsistency *)
  if options.check_level_consistency then begin
    (* Check if any filter is more restrictive than min_level *)
    let has_level_filter =
      List.exists (fun filter ->
        (* Heuristic: check if filter mentions level *)
        (* In practice, we'd need to introspect the filter function *)
        true) config.filters
    in
    
    (* Check for redundant level filters *)
    let level_filters =
      List.filter_map (fun filter ->
        (* Try to detect level-based filters *)
        None) config.filters
    in
    
    if List.length level_filters > 1 then
      warnings := 
        "Multiple level filters configured - consider using minimum_level instead" 
        :: !warnings
  end;
  
  (* Check 3: Sink configuration issues *)
  if options.check_sink_configs then begin
    List.iteri (fun i (sink_config : sink_config) ->
      match sink_config.min_level with
      | Some sink_level ->
          if Level.compare sink_level config.min_level < 0 then
            warnings := 
              Printf.sprintf "Sink %d has lower min_level (%s) than logger (%s) - \
                             sink will receive filtered events" 
                i (Level.to_string sink_level) (Level.to_string config.min_level)
              :: !warnings
      | None -> ()
    ) config.sinks
  end;
  
  (* Check 4: High verbosity in production-like settings *)
  if options.warn_high_verbosity then begin
    if config.min_level = Level.Verbose || config.min_level = Level.Debug then
      warnings :=
        Printf.sprintf "Low minimum_level (%s) may impact performance in production"
          (Level.to_string config.min_level)
        :: !warnings
  end;
  
  (* Check 5: Sink conflicts *)
  if options.check_sink_configs then begin
    let file_sinks = 
      List.filter (fun (sc : sink_config) ->
        (* Detect file sinks by checking if path exists in config *)
        (* This requires tracking sink type in sink_config *)
        false) config.sinks
    in
    
    (* Check for duplicate file paths *)
    let paths = ref [] in
    List.iteri (fun i (sc : sink_config) ->
      (* Would need to extract path from sink_fn *)
      ()
    ) config.sinks
  end;

  (* Return result *)
  match !errors, !warnings with
  | [], [] -> Valid
  | [], ws -> Warning (List.rev ws)
  | es, _ -> Error (List.rev es)

let create_logger_validated ?options config =
  match validate ?options config with
  | Valid -> create_logger config
  | Warning ws ->
      List.iter (fun w -> Printf.eprintf "Configuration warning: %s\n" w) ws;
      create_logger config
  | Error es ->
      List.iter (fun e -> Printf.eprintf "Configuration error: %s\n" e) es;
      raise (Invalid_argument "Configuration validation failed")
```

### Step 3: Add Better Configuration Tracking

To enable better validation, track sink metadata:

```ocaml
type sink_metadata =
  { id: string
  ; sink_type: [Console | File | Json | Null | Custom]
  ; path: string option  (* for file sinks *)
  ; description: string }

type sink_config =
  { sink_fn: Composite_sink.sink_fn
  ; min_level: Level.t option
  ; metadata: sink_metadata }
```

Update `add_sink` to populate metadata:

```ocaml
let add_sink ?min_level ?(metadata={id="unknown"; sink_type=Custom; path=None; description=""}) 
    ~create ~emit ~flush ~close config =
  let sink = create () in
  let sink_fn = ... in
  {config with sinks= {sink_fn; min_level; metadata} :: config.sinks}
```

### Step 4: Enhanced Validation Checks

```ocaml
let validate ?(options=default_validation_options) config =
  let warnings = ref [] in
  let errors = ref [] in
  
  (* Improved Check: Duplicate file paths *)
  let file_paths = ref [] in
  List.iter (fun (sc : sink_config) ->
    match sc.metadata.sink_type, sc.metadata.path with
    | File, Some path ->
        if List.mem path !file_paths then
          errors := 
            Printf.sprintf "Multiple file sinks writing to same path: %s" path
            :: !errors
        else
          file_paths := path :: !file_paths
    | _ -> ()
  ) config.sinks;
  
  (* Check: Console colors with stderr redirection *)
  let console_sinks = 
    List.filter (fun sc -> sc.metadata.sink_type = Console) config.sinks
  in
  if List.length console_sinks > 1 then
    warnings := 
      "Multiple console sinks configured - consider using a single console sink"
      :: !warnings;
  
  (* Check: No async queue with sync file sink *)
  (* Would need to track queue usage *)
  
  (* Check: Circuit breaker without error handler *)
  (* Would need to track circuit breaker config *)
  
  ...
```

### Step 5: Configuration Debug Mode

Add a debug mode that prints the effective configuration:

```ocaml
val to_string : t -> string

let to_string config =
  let sink_strs = 
    List.mapi (fun i (sc : sink_config) ->
      Printf.sprintf "  Sink %d: %s (min_level: %s)"
        i
        sc.metadata.description
        (match sc.min_level with
         | Some l -> Level.to_string l
         | None -> "inherit")
    ) config.sinks
  in
  
  String.concat "\n" 
    ([ Printf.sprintf "Logger Configuration:"
     ; Printf.sprintf "  Minimum Level: %s" (Level.to_string config.min_level)
     ; Printf.sprintf "  Sinks: %d" (List.length config.sinks)
     ] @ sink_strs @
     [ Printf.sprintf "  Enrichers: %d" (List.length config.enrichers)
     ; Printf.sprintf "  Filters: %d" (List.length config.filters)
     ; Printf.sprintf "  Context Properties: %d" 
         (List.length config.context_properties)
     ])
```

### Step 6: Strict Mode

Add a strict mode that turns warnings into errors:

```ocaml
val create_strict : unit -> t
(** Create configuration that validates on every modification *)

type strict_config =
  { config: t
  ; validation_options: validation_options }

let minimum_level level sc =
  let new_config = {sc.config with min_level= level} in
  match validate ~options:sc.validation_options new_config with
  | Valid -> {sc with config= new_config}
  | Warning ws ->
      if sc.validation_options.treat_warnings_as_errors then
        failwith (String.concat "\n" ws)
      else
        {sc with config= new_config}
  | Error es -> failwith (String.concat "\n" es)
```

## Usage Examples

### Example 1: Basic Validation

```ocaml
let config =
  Configuration.create ()
  |> Configuration.minimum_level Level.Debug
  |> Configuration.write_to_console ~colors:true ()
  |> Configuration.write_to_file "app.log"

(* Validate before creating logger *)
match Configuration.validate config with
| Valid ->
    let logger = Configuration.create_logger config in
    Log.set_logger logger
| Warning ws ->
    List.iter print_endline ws;
    let logger = Configuration.create_logger config in
    Log.set_logger logger
| Error es ->
    List.iter prerr_endline es;
    exit 1
```

### Example 2: Validated Creation

```ocaml
(* Raises on validation error *)
let logger =
  Configuration.create ()
  |> Configuration.minimum_level Level.Information
  |> Configuration.write_to_console ()
  |> Configuration.create_logger_validated
```

### Example 3: Debug Configuration

```ocaml
let config =
  Configuration.create ()
  |> Configuration.verbose
  |> Configuration.write_to_console ()
  |> Configuration.write_to_file "/var/log/app.log"
  |> Configuration.filter_by (Filter.level_filter Level.Error)

(* Print effective configuration *)
print_endline (Configuration.to_string config);
(* Output:
   Logger Configuration:
     Minimum Level: Verbose
     Sinks: 2
       Sink 0: console (min_level: inherit)
       Sink 1: file /var/log/app.log (min_level: inherit)
     Enrichers: 0
     Filters: 1
     Context Properties: 0
*)

(* Validate *)
match Configuration.validate config with
| Warning ["Low minimum_level (Verbose) may impact performance";
           "Multiple level filters configured - consider using minimum_level instead"] ->
    print_endline "Review configuration warnings"
| _ -> ()
```

### Example 4: Strict Mode

```ocaml
let config =
  Configuration.create_strict ()
  |> Configuration.minimum_level Level.Debug
(* Raises immediately if Debug level conflicts with other settings *)
```

## Testing Strategy

### Unit Tests

```ocaml
let test_validation_no_sinks () =
  let config = Configuration.create () in
  match Configuration.validate config with
  | Warning ["No sinks configured"] -> ()
  | _ -> fail "Expected warning about no sinks"

let test_validation_duplicate_file_paths () =
  let config =
    Configuration.create ()
    |> Configuration.write_to_file "same.log"
    |> Configuration.write_to_file "same.log"
  in
  match Configuration.validate config with
  | Error ["Multiple file sinks writing to same path: same.log"] -> ()
  | _ -> fail "Expected error about duplicate paths"

let test_validation_level_consistency () =
  let config =
    Configuration.create ()
    |> Configuration.minimum_level Level.Error
    |> Configuration.filter_by (Filter.level_filter Level.Debug)
  in
  match Configuration.validate config with
  | Warning ["Multiple level filters configured"] -> ()
  | _ -> fail "Expected warning about multiple level filters"
```

### Integration Tests

```ocaml
let test_validated_creation_raises_on_error () =
  let config = Configuration.create () in  (* No sinks *)
  try
    ignore (Configuration.create_logger_validated config);
    fail "Should have raised"
  with Invalid_argument _ -> ()
```

## Migration Guide

### For Library Users

**No breaking changes** - validation is optional.

**New recommended pattern:**
```ocaml
(* Before *)
let logger =
  Configuration.create ()
  |> Configuration.write_to_file "app.log"
  |> Configuration.create_logger

(* After (recommended) *)
let logger =
  Configuration.create ()
  |> Configuration.write_to_file "app.log"
  |> Configuration.create_logger_validated
```

## Success Criteria

- [ ] Validation function implemented
- [ ] Warning detection for common issues
- [ ] Error detection for invalid configs
- [ ] to_string function for debugging
- [ ] Validated creation function
- [ ] All validation paths tested
- [ ] Documentation with examples

## Related Files

- `lib/configuration.ml`
- `lib/configuration.mli`
- `test/test_configuration.ml`

## Notes

- Start with basic validation, expand over time
- Consider adding automatic fix suggestions ("Did you mean...")
- Could integrate with OCaml's warning system for compile-time feedback
