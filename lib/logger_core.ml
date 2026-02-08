(** Core logger functionality shared across sync, Lwt, and Eio implementations
*)

(** Monad signature for the logger's effect system *)
module type MONAD = sig
  type 'a t

  val return : 'a -> 'a t

  val bind : 'a t -> ('a -> 'b t) -> 'b t

  val iter_p : ('a -> unit t) -> 'a list -> unit t
end

(** Logger implementation type - parameterized by the sink type *)
type 'sink logger_impl =
  { min_level: Level.t
  ; sinks: ('sink * Level.t option) list
  ; enrichers: (Log_event.t -> Log_event.t) list
  ; filters: (Log_event.t -> bool) list
  ; context_properties: (string * Yojson.Safe.t) list
  ; source: string option }

(** Identity monad for synchronous operations *)
module Identity = struct
  type 'a t = 'a

  let return x = x

  let bind x f = f x

  let iter_p f lst = List.iter f lst; ()
end

(** Functor to create a logger for the given monad and sink *)
module Make
    (M : MONAD)
    (Sink_fn : sig
      type sink

      val emit_fn : sink -> Log_event.t -> unit M.t

      val flush_fn : sink -> unit M.t

      val close_fn : sink -> unit M.t
    end) =
struct
  type t =
    { min_level: Level.t
    ; sinks: (Sink_fn.sink * Level.t option) list
    ; enrichers: (Log_event.t -> Log_event.t) list
    ; filters: (Log_event.t -> bool) list
    ; context_properties: (string * Yojson.Safe.t) list
    ; source: string option }

  (** Check if a level is enabled *)
  let is_enabled t level = Level.compare level t.min_level >= 0

  (** Check if event passes all filters *)
  let passes_filters t event =
    List.for_all (fun filter -> filter event) t.filters
  ;;

  (** Apply all enrichers to an event *)
  let apply_enrichers t event =
    List.fold_left (fun ev enricher -> enricher ev) event t.enrichers
  ;;

  (** Add context properties to an event *)
  let add_context_properties t event =
    let ambient_props = Log_context.current_properties () in
    let correlation_id = Log_context.get_correlation_id () in
    if ambient_props = [] && t.context_properties = [] && correlation_id = None
    then
      event
    else
      let current_props = Log_event.get_properties event in
      let new_props = ambient_props @ t.context_properties @ current_props in
      Log_event.create
        ~timestamp:(Log_event.get_timestamp event)
        ~level:(Log_event.get_level event)
        ~message_template:(Log_event.get_message_template event)
        ~rendered_message:(Log_event.get_rendered_message event)
        ~properties:new_props
        ?exception_info:(Log_event.get_exception event)
        ?correlation_id:
          ( match correlation_id with
          | None -> Log_event.get_correlation_id event
          | Some _ -> correlation_id )
        ()
  ;;

  (** Core write method *)
  let write t ?exn level message_template properties =
    (* Fast path: check minimum level first *)
    if not (is_enabled t level) then
      M.return ()
    else
      (* Create the log event *)
      let rendered_message =
        Runtime_helpers.render_template message_template properties
      in
      let correlation_id = Log_context.get_correlation_id () in
      let event =
        Log_event.create ~level ~message_template ~rendered_message ~properties
          ?exception_info:exn ?correlation_id ()
      in

      (* Apply enrichment pipeline *)
      let event = apply_enrichers t event in
      let event = add_context_properties t event in

      (* Check filters *)
      if not (passes_filters t event) then
        M.return ()
      else
        (* Emit to all sinks with per-sink level filtering *)
        M.iter_p
          (fun (sink, min_level) ->
            match min_level with
            | Some min_lvl when Level.compare level min_lvl < 0 -> M.return ()
            | _ -> Sink_fn.emit_fn sink event )
          t.sinks
  ;;

  (** Level-specific convenience methods *)
  let verbose t ?exn message properties =
    write t ?exn Level.Verbose message properties
  ;;

  let debug t ?exn message properties =
    write t ?exn Level.Debug message properties
  ;;

  let information t ?exn message properties =
    write t ?exn Level.Information message properties
  ;;

  let warning t ?exn message properties =
    write t ?exn Level.Warning message properties
  ;;

  let error t ?exn message properties =
    write t ?exn Level.Error message properties
  ;;

  let fatal t ?exn message properties =
    write t ?exn Level.Fatal message properties
  ;;

  (** Create a contextual logger with additional property *)
  let for_context t name value =
    {t with context_properties= (name, value) :: t.context_properties}
  ;;

  (** Add an enricher function *)
  let with_enricher t enricher = {t with enrichers= enricher :: t.enrichers}

  (** Create a sub-logger for a specific source *)
  let for_source t source_name = {t with source= Some source_name}

  (** Create a logger *)
  let create ~min_level ~sinks =
    { min_level
    ; sinks
    ; enrichers= []
    ; filters= []
    ; context_properties= []
    ; source= None }
  ;;

  (** Helper to add a minimum level filter *)
  let add_min_level_filter t min_level =
    let filter event =
      Level.compare (Log_event.get_level event) min_level >= 0
    in
    {t with filters= filter :: t.filters}
  ;;

  (** Add a custom filter function *)
  let add_filter t filter = {t with filters= filter :: t.filters}

  (** Flush all sinks *)
  let flush t = M.iter_p (fun (sink, _) -> Sink_fn.flush_fn sink) t.sinks

  (** Close all sinks *)
  let close t = M.iter_p (fun (sink, _) -> Sink_fn.close_fn sink) t.sinks
end
