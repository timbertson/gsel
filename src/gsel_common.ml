open Log

open Sexplib.Std

type run_options = {
	print_index : bool;
	display_env : string option;
} with sexp

type program_mode =
	| GSEL_SERVER
	| GSEL_STANDALONE
	| GSEL_CLIENT

type program_options = {
	run_options : run_options;
	program_mode: program_mode;
	server_address : string option;
}

let starts_with str prefix =
	try (String.sub str 0 (String.length prefix)) == prefix
	with Invalid_argument _ -> false

let remove_leading str prefix =
	assert (starts_with str prefix);
	let pre = (String.length prefix) in
	let len = (String.length str) - pre in
	String.sub str pre len


let parse_args () =
	let print_index = ref false in
	let server_mode = ref false in
	let client_mode = ref false in
	let server_address = ref None in

	(* parse args *)
	let addr_prefix = "--addr=" in
	let rec process_args args = match args with
		| [] -> ()
		| "-h" :: args
		| "--help" :: args ->
				prerr_string (
					"Usage: gsel [OPTIONS]\n"^
					"\n"^
					"Options:\n"^
					"  --index:     Print out the index (input line number)\n"^
					"               of the selected option, rather than its contents\n"^
					"  --server:    Run a server\n"^
					"  --client:    Connect to a server (falls back to normal operation\n"^
					"               if no server is available)\n"^
					"  --addr=ADDR: Server address (use with --client / --server)\n"^
					""
				);
				exit 0

		| "--index" :: args ->
				print_index := true;
				process_args args

		| "--server" :: args ->
				server_mode := true;
				process_args args

		| "--client" :: args ->
				client_mode := true;
				process_args args

		| flag :: args when starts_with flag addr_prefix ->
				server_address := Some (remove_leading flag addr_prefix);
				process_args args

		| "--addr" :: addr :: args ->
				server_address := Some addr;
				process_args args

		| unknown :: _ -> failwith ("Unknown argument: " ^ unknown)
	in
	process_args (List.tl (Array.to_list Sys.argv));
	let mode = match !server_mode, !client_mode with
		| true, false -> GSEL_SERVER
		| false, true -> GSEL_CLIENT
		| false, false -> GSEL_STANDALONE
		| _ -> failwith "Conflicting --client / --server options"
	in
	{
		program_mode = mode;
		server_address = !server_address;
		run_options = {
			print_index = !print_index;
			display_env = try Some (Unix.getenv "DISPLAY") with Not_found -> None;
		};
	}

let init_socket opts =
	let open Unix in
	let fd = socket PF_UNIX SOCK_STREAM 0 in
	let socket_path =
		(match opts.server_address with
			| Some path -> path
			| None -> (
				try Unix.getenv "GSEL_SERVER_ADDRESS"
				with Not_found -> Filename.concat (
					try Unix.getenv "XDG_RUNTIME_DIR"
					with Not_found -> "/tmp" (* XXX this is not per-user, so it could collide *)
				) "gsel.sock"
			)
	) in
	debug "Server address: %s" socket_path;
	let addr = ADDR_UNIX ("\000" ^ socket_path) in
	(fd, "unix:abstract:"^socket_path, addr)
;;

let init_background_thread () =
	(* block these signals so that they are delivered to the main thread *)
	let (_:int list) = Thread.sigmask Unix.SIG_BLOCK [Sys.sigint; Sys.sigpipe] in
	()
;;


type response =
	| Success of string
	| Error of string
	| Cancelled

class stdin_input = object
	method read_line =
		try Some (input_line stdin)
		with End_of_file -> None

	method respond response = match response with
		| Success response -> print_endline response
		| Error str -> prerr_endline str
		| Cancelled -> ()
end

class stream_input fd =
	let r = Unix.in_channel_of_descr fd
	and w = Unix.out_channel_of_descr fd
	and eof = '\000'
	in
	object
	method read_line =
		let line = input_line r in
		if String.contains line eof then None
		else Some line

	method respond response =
		let mode, response = match response with
			| Success response -> ('y', response)
			| Error response -> ('n', response)
			| Cancelled -> ('n', "")
		in
		output_char w mode;
		output_string w response;
		output_char w '\n';
		flush w;
		Unix.(shutdown fd SHUTDOWN_ALL);
		Unix.close fd
end

let init_logging () =
	enable_debug := try Unix.getenv "GSEL_DEBUG" = "1" with Not_found -> false
