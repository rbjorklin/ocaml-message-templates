(** Logging with automatic JSON deriving example

    This example demonstrates how to use ppx_deriving_yojson to automatically
    generate JSON converters for your custom types, making logging seamless.

    To use this in your own projects: 1. Add ppx_deriving_yojson to your
    dependencies 2. Add [@@deriving yojson] to your types 3. Use the generated
    *_to_yojson functions with the Log module *)

open Message_templates

(* Define custom types with automatic JSON conversion *)
type user =
  { id: int
  ; name: string
  ; email: string
  ; active: bool }
[@@deriving yojson]
(* This generates: user_to_yojson and user_of_yojson *)

type request_status =
  | Pending
  | Processing
  | Completed
  | Failed of string
[@@deriving yojson]
(* This generates: request_status_to_yojson and request_status_of_yojson *)

type request =
  { request_id: string
  ; user: user
  ; endpoint: string
  ; status: request_status
  ; duration_ms: float option }
[@@deriving yojson]

let () =
  (* Configure the logger *)
  let logger =
    Configuration.create ()
    |> Configuration.information
    |> Configuration.write_to_console ~colors:true ()
    |> Configuration.write_to_file "deriving_example.log"
    |> Configuration.create_logger
  in

  Log.set_logger logger;

  (* Create some sample data *)
  let user1 =
    {id= 1; name= "Alice Smith"; email= "alice@example.com"; active= true}
  in

  let user2 =
    {id= 2; name= "Bob Jones"; email= "bob@example.com"; active= false}
  in

  (* Log user data - automatic JSON conversion! *)
  Log.information "User created" [("user", user_to_yojson user1)];

  Log.information "User created" [("user", user_to_yojson user2)];

  (* Log requests with nested custom types *)
  let request1 =
    { request_id= "req-001"
    ; user= user1
    ; endpoint= "/api/users"
    ; status= Completed
    ; duration_ms= Some 45.5 }
  in

  let request2 =
    { request_id= "req-002"
    ; user= user2
    ; endpoint= "/api/orders"
    ; status= Failed "Database connection timeout"
    ; duration_ms= None }
  in

  Log.information "Request processed" [("request", request_to_yojson request1)];

  Log.error "Request failed" [("request", request_to_yojson request2)];

  (* Demonstrate using context with complex types *)
  Log_context.with_property "current_user" (user_to_yojson user1) (fun () ->
      Log.information "Performing admin operation" [];

      (* Update request status *)
      let updated_request = {request1 with status= Processing} in
      Log.debug "Request status updated"
        [("request", request_to_yojson updated_request)] );

  (* Demonstrate list of custom types *)
  let users = [user1; user2] in
  let users_json = `List (List.map user_to_yojson users) in
  Log.information "User list retrieved"
    [("users", users_json); ("count", `Int (List.length users))];

  (* Cleanup *)
  Log.close_and_flush ();

  print_endline "\nppx_deriving_yojson example completed!";
  print_endline "";
  print_endline "Check deriving_example.log for the JSON output.";
  print_endline "";
  print_endline "The generated JSON for a user looks like:";
  print_endline (Yojson.Safe.to_string (user_to_yojson user1))
;;
