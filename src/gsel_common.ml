open Log

open Sexplib.Std

type run_options = {
	print_index : bool;
	display_env : string option;
} [@@deriving sexp]

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

type rpc_format = {
	item : char;
	query : char;
	eof : char;
	nl : char;
	selection : char;
	failure : char;
	options : char;
}

let rpc = {
	item = '+';
	query = '/';
	selection = '>';
	failure = 'n';
	options = '#';
	eof = '\000';
	nl = '\n';
}

let string_of_char = String.make 1


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
	debug "Server address: @%s" socket_path;
	let addr = ADDR_UNIX ("\000" ^ socket_path) in
	(fd, "unix:abstract:"^socket_path, addr)
;;

let init_background_thread () =
	(* block these signals so that they are delivered to the main thread *)
	let (_:int list) = Thread.sigmask Unix.SIG_BLOCK [Sys.sigint; Sys.sigpipe] in
	()
;;

let with_tty (type a) : (Unix.file_descr option -> a) -> a = fun fn ->
	let open Unix in
	let tty = if Unix.isatty Unix.stdin then (
		(* XXX set gui message? *)
		prerr_endline "WARN: stdin is a terminal";
		None
	) else (
		try
			Some Unix.(openfile "/dev/tty" [O_RDONLY; O_NONBLOCK] 0o000)
		with Unix.Unix_error (err, fn, arg) -> (
			debug "%s %s: %s" fn arg (Unix.error_message err);
			None
		)
	) in
	match tty with
		| None -> fn None
		| Some ttyfd ->
			Sys.set_signal Sys.sigttou (Sys.Signal_handle ignore);
			let original = tcgetattr ttyfd in
			let mode = TCSADRAIN in
			(* icanon = wait for newline; echo = display input *)
			let reset = try
				tcsetattr ttyfd mode { original with c_icanon = false; c_echo = false; };
				fun () -> tcsetattr ttyfd mode original
			with Unix.Unix_error (Unix.EINTR, _, _) -> (
				prerr_endline "[gsel] WARN: can't access TTY";
				fun () -> ()
			) in
			let rv = try fn tty with e -> (reset (); raise e) in
			reset ();
			rv

type input =
	| Item of string
	| Query of string
	| Options of string

let string_of_input = function
	| Item s -> "Item \"" ^ s ^ "\""
	| Query s -> "Query \"" ^ s ^ "\""
	| Options s -> "Options \"" ^ s ^ "\""

let input_of_line contents =
	if String.contains contents rpc.eof
		then None
		else try Some (
			let mode = String.get contents 0
			and contents = String.sub contents 1 (String.length contents - 1)
			in
			if mode = rpc.item
				then (Item contents)
			else if mode = rpc.query
				then (Query contents)
			else if mode = rpc.options
				then (Options contents)
			else failwith ("Invalid input mode: " ^ (string_of_char mode))
		) with Not_found -> None

type response =
	| Success of string
	| Error of string
	| Cancelled

type emitter_feedback =
	| Continue
	| Stop

let consume_lines read_line emitter =
	let rec loop () = (
		match read_line () with
			| None -> debug "input complete"; ()
			| Some line -> (
				match emitter line with
					| Stop -> ()
					| Continue -> loop ()
			)
	) in
	loop ()

class type source = object
	method read_options_header : string option
	method consume : (input -> emitter_feedback) -> unit
	method respond : response -> unit
	method repr : string
end

class stdin_input : source =
	let read_line () =
		(* stdin only allows item input *)
		try Some (Item (input_line stdin))
		with End_of_file -> None
	in
	object (self)
	method repr = "<#stdin>"
	
	method read_options_header : string option = None (* not supported *)
	
	method consume emitter = consume_lines read_line emitter

	method respond response = match response with
		| Success response -> print_endline response
		| Error str -> prerr_endline str
		| Cancelled -> ()
end

class socket_input fd : source =
	let r = Unix.in_channel_of_descr fd
	and w = Unix.out_channel_of_descr fd
	in
	let read_line () = input_of_line (input_line r) in
	object (self)
	method repr = "<#socket>"
	method read_options_header = match read_line () with
		| Some (Options opts) -> Some opts
		| None -> None
		| Some other -> failwith ("expected options, got " ^ (string_of_input other))
	
	method consume emitter = consume_lines read_line emitter

	method respond response =
		let mode, response = match response with
			| Success response -> (rpc.selection, response)
			| Error response -> (rpc.failure, response)
			| Cancelled -> (rpc.failure, "")
		in
		output_char w mode;
		output_string w response;
		output_char w rpc.nl;
		flush w;
		Unix.(shutdown fd SHUTDOWN_ALL);
		Unix.close fd
end

exception Stop_emitting

class terminal_input ~tty ~timeout : source =
	let buflen = 500 in
	let nlre = Str.regexp "\n" in

	let consume_lines buf len = (
		let open Unix in
		let trim_leading idx =
			let new_start = idx + 1 in
			let new_len = len - new_start in
			Bytes.blit buf new_start buf 0 new_len;
			new_len
		in
		let last_newline =
			try Some (Bytes.rindex_from buf (len - 1) '\n')
			with Not_found -> None
		in
		match last_newline with
			| Some idx ->
				let lines = Bytes.sub_string buf 0 (idx) in
				(Str.split_delim nlre lines, trim_leading idx)
			| None ->
				if len >= buflen then (
					(* no newline found still, just break it *)
					let contents = Bytes.sub_string buf 0 len in
					([contents], trim_leading (len - 1))
				) else ([], len)
	) in

	let read_stdin = (
		let open Unix in
		let len = ref 0 in
		let buf = Bytes.create (2*buflen) in
		fun source -> (
			let bytes_read = read source buf !len (buflen - !len) in
			debug "read %d bytes from source" bytes_read;
			if bytes_read = 0 then (
				(* EOF *)
				None
			) else (
				len := !len + bytes_read;
				let lines, new_len = consume_lines buf !len in
				len := new_len;
				Some (lines |> List.map (fun line -> Item line))
			)
		)
	) in

	let read_tty = (
		let open Unix in
		let buf = Bytes.create buflen in
		fun source -> (
			let bytes_read = read source buf 0 buflen in
			debug "read %d bytes from TTY" bytes_read;
			if bytes_read = 0 then (
				(* EOF *)
				None
			) else (
				match Bytes.get buf 0 with
					(* discard messages beginning with special characters (backspace, arrow keys, etc) *)
					| '\127' | '\027' | '\n' ->
						debug "ignoring non-text message";
						Some []
					| _ ->
						let contents = Bytes.sub_string buf 0 bytes_read in
						Some [Query contents]
			)
		)
	) in

	let read_input source =
		if source = tty then read_tty source else read_stdin source
	in
	let stdin_source = new stdin_input in
	let sources = ref [tty; Unix.stdin] in
	let stop () = () in
object
	method repr = "<#terminal_input>"
	method read_options_header = stdin_source#read_options_header
	method consume emitter =
		let open Unix in
		let rec loop () =
			let readable, _writable, _err = select !sources [] [] timeout in
			debug "select returned %d readable resources out of %d" (List.length readable) (List.length !sources);
			let next : unit -> unit = (
				try
					readable |> List.iter (fun source ->
						match read_input source with
							| None ->
								sources := !sources |> List.filter ((<>) source);
								()
							| Some items ->
								items |> List.iter (fun item ->
									match emitter item with
										| Continue -> ()
										| Stop -> raise Stop_emitting
								)
					);
					loop
				with Stop_emitting -> stop
			) in
			next ()
		in loop ()

	method respond response = stdin_source#respond response
end

let terminal_source ~tty = match tty with
	| Some tty -> new terminal_input ~tty ~timeout:120.0
	| None -> new stdin_input

let init_logging () =
	enable_debug := try Unix.getenv "GSEL_DEBUG" = "1" with Not_found -> false
