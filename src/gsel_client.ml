open Log
open Gsel_common
open Sexplib

let run_inner opts ~tty fd =
	(* the server agressively closes the socket when it's
	 * done handling a request. So the client can ignore SIGPIPE *)
	Sys.set_signal Sys.sigpipe Sys.Signal_ignore;

	let dest = Unix.out_channel_of_descr fd in

	(* send initial opts *)
	let serialized_opts = Sexp.to_string_mach
		(sexp_of_run_options opts.run_options) in
	debug "serialized opts: %s" serialized_opts;
	output_char dest rpc.options;
	output_string dest serialized_opts;
	output_char dest rpc.nl;
	flush dest;

	let (_:Thread.t) =
		let source = terminal_source ~tty opts in
		let run () =
			try (
				source#consume (function
					| Options _ -> failwith "options not supported"
					| Item line ->
						debug "sending line: \"%s\"" (String.escaped line);
						output_char dest rpc.item;
						output_string dest line;
						output_char dest rpc.nl;
						Continue
					| Query q ->
						debug "sending query string: \"%s\"" (String.escaped q);
						output_char dest rpc.query;
						output_string dest q;
						output_char dest rpc.nl;
						flush dest;
						Continue
				)
			) with e -> debug "input loop failed with %s" (Printexc.to_string e);
		in
		Thread.create (fun () ->
			init_background_thread ();
			run ()
		) ()
	in

	let response_stream = Unix.in_channel_of_descr fd in
	let mode = input_char response_stream in
	let response = input_line response_stream in
	debug "got response %c|%s" mode response;
	let status =
		if mode = rpc.selection
			then (print_endline response; 0)
		else if mode = rpc.failure
			then (prerr_endline response; 1)
		else failwith (Printf.sprintf "Unknown response type %c" mode)
	in
	status
;;

let run opts =
	let fd, path, addr = init_socket opts in
	if (
		try Unix.connect fd addr; true
		with Unix.Unix_error (Unix.ECONNREFUSED, _, _) -> begin
			Unix.close fd;
			Printf.eprintf "WARN: No server found at %s\n" path;
			false
		end
	) then (
		with_tty (fun tty ->
			Some (run_inner opts ~tty fd)
		)
	) else None

let main () =
	init_logging ();
	let opts = parse_args () in
	let code = Option.default (run opts) 1 in
	exit code
