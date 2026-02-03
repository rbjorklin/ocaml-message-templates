open Message_templates

let () =
  let events = ref [] in
  let emit_fn event = events := event :: !events in
  
  let config = { 
    Async_sink_queue.default_config with 
    max_queue_size = 3; 
    flush_interval_ms = 10000 
  } in
  
  Printf.printf "Creating queue...\n%!";
  let queue = Async_sink_queue.create config emit_fn in
  
  Printf.printf "Adding 5 events...\n%!";
  for i = 1 to 5 do
    Printf.printf "  Event %d...\n%!" i;
    let event =
      Log_event.create ~level:Level.Information
        ~message_template:"Msg"
        ~rendered_message:"Msg"
        ~properties:[]
        ()
    in
    Async_sink_queue.enqueue queue event;
    let depth = Async_sink_queue.get_queue_depth queue in
    Printf.printf "    Depth after: %d\n%!" depth
  done;
  
  Printf.printf "Checking depth...\n%!";
  let depth = Async_sink_queue.get_queue_depth queue in
  Printf.printf "Depth: %d (expected 3)\n%!" depth;
  
  Printf.printf "Getting stats...\n%!";
  let stats = Async_sink_queue.get_stats queue in
  Printf.printf "Dropped: %d (expected 2)\n%!" stats.total_dropped;
  
  Printf.printf "Closing...\n%!";
  Async_sink_queue.close queue;
  Printf.printf "Done!\n%!"
