(** Filter predicates for log events *)

(** Filter function type *)
type t = Log_event.t -> bool

(** Filter by minimum level - events must be at least this level *)
let level_filter min_level event =
  let event_level = Log_event.get_level event in
  Level.compare event_level min_level >= 0

(** Filter by property value - event must have the property and pass the predicate *)
let property_filter property_name predicate event =
  let properties = Log_event.get_properties event in
  match List.assoc_opt property_name properties with
  | Some value -> predicate value
  | None -> false

(** Filter that matches if a property name exists (regardless of value) *)
let matching property_name event =
  let properties = Log_event.get_properties event in
  List.mem_assoc property_name properties

(** Combine multiple filters with AND logic - all must pass *)
let all filters event =
  List.for_all (fun filter -> filter event) filters

(** Combine multiple filters with OR logic - any can pass *)
let any filters event =
  List.exists (fun filter -> filter event) filters

(** Negate a filter *)
let not_filter filter event =
  not (filter event)

(** Always include filter - passes everything *)
let always_pass _event = true

(** Always exclude filter - blocks everything *)
let always_block _event = false
