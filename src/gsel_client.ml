open Log
open Gsel_common

let run_inner fd =
	let source = (new stdin_input) in
	let dest = Unix.out_channel_of_descr fd in
	let rec loop () =
		match source#read_line with
			| Some line ->
				output_string dest line;
				output_char dest '\n';
				loop ()

			| None ->
				debug "input complete";
				output_char dest '\000';
				output_char dest '\n';
				flush dest;
				()
	in
	let (_:Thread.t) = Thread.create (fun () ->
		init_background_thread ();
		loop ()
	) () in

	let response_stream = Unix.in_channel_of_descr fd in
	let typ = input_char response_stream in
	let response = input_line response_stream in
	let status = match typ with
		| 'y' -> print_string response; 0
		| 'n' -> prerr_string response; 0
		| t -> failwith (Printf.sprintf "Unknown response type %c" t)
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
		Some (run_inner fd)
	) else None

let main () =
	init_logging ();
	let opts = parse_args () in
	let code = Option.default (run opts) 1 in
	exit code
