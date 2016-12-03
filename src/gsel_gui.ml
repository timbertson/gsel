open Log
open Search
open Gsel_common

open Sexplib

module SortedSet = struct
	type t = entry list
	let cmp a b =
		let a = a.text and b = b.text in
		let len_diff = String.length a - String.length b in
		if len_diff <> 0
			then len_diff
			else String.compare a b

	let create () : t = []
	let rec add (existing : t) (elem : entry) =
		match existing with
			| [] -> [elem]
			| head :: tail ->
					if elem = head then existing (* ignore duplicates *) else
						if (cmp elem head) <= 0
							then elem :: existing
							else head :: (add tail elem)
end

type redraw_reason = New_input | New_query

class server fd = object
	method accept : source =
		let stream, _addr = Unix.accept fd in
		new socket_input stream
end

let rec list_take n lst = if n = 0 then [] else match lst with
	| x::xs -> x :: list_take (n-1) xs
	| [] -> []

let findi lst pred =
	let rec loop i l =
		match l with
		| head::tail ->
				if (pred head) then (Some i)
				else loop (i+1) tail
		| [] -> None
	in
	loop 0 lst

let escape_html =
	let amp = Str.regexp "&" in
	let special = Str.regexp "[<>]" in
	fun s -> s
		|> Str.global_replace amp "&amp;"
		|> Str.global_substitute special (function
			| ">" -> "&gt;"
			| "<" -> "&lt;"
			| _ -> failwith "impossible"
		)

let markup_escape text = ignore text; failwith "TODO"

let markup str indexes =
	let open Search.Highlight in
	let parts = Search.highlight str indexes in
	let parts = List.map (function
		(* XXX define a style somewhere or use programmatic style attributes rather than
		 * building ugly html strings *)
		| Highlighted s -> "<span color=\"#eeeeee\" weight=\"bold\" underline=\"low\" underline_color=\"#888888\">" ^ markup_escape s ^ "</span>"
		| Plain s -> markup_escape s
	) parts in
	String.concat "" parts
;;

let input_loop ~source ~append_query ~modify_all_items ~finish () =
	let i = ref 0 in
	let nonempty_line = ref false in

	let max_items = try int_of_string (Unix.getenv "GSEL_MAX_ITEMS") with Not_found -> 10000 in
	source#consume (function
		| Options _ -> Continue
		| EOF -> Continue
		| Query text ->
			debug "append query text: %s" text;
			append_query text;
			Continue
		| Item line ->
			if not !nonempty_line && String.length line > 0 then
				nonempty_line := true
			;
			debug "item[%d]: %s" !i line;
			modify_all_items (fun all_items ->
				SortedSet.add all_items {
					text=line;
					match_text=String.lowercase_ascii line;
					input_index=(!i);
				}
			);
			i := !i+1;

			(* give UI a chance to keep up *)
			if ((!i mod 500) = 0) then (
				Thread.delay 0.1
			);

			if (!i = max_items) then (
				debug "capping items at %d" max_items;
				Stop
			) else (
				Continue
			)
	);
	if not !nonempty_line then (
		finish (Error "No input received");
	)
;;

let gui_inner ~source ~opts ~exit () =
	debug "gui running from source: %s" source#repr;
	let all_items = ref (SortedSet.create ()) in
	let shown_items = ref [] in
	let last_query = ref "" in
	let selected_index = ref 0 in
	let get_selected_item () = List.nth !shown_items !selected_index in

	let all_items_mutex = Mutex.create () in
	let shown_items_mutex = Mutex.create () in
	let query_mutex = Mutex.create () in
	let with_mutex (type a) : Mutex.t -> (unit -> a) -> a =
		fun m fn ->
			Mutex.lock m;
			let rv = try fn ()
				with e -> (Mutex.unlock m; raise e) in
			Mutex.unlock m;
			rv
	in

	let selection_changed i =
		debug "selected index is now %d" i;
		selected_index := i
	in

	let ui_ = ref None in
	let with_ui fn =
		match !ui_ with
			| Some ui -> fn ui
			| None -> ()
	in

	let redraw reason =
		let all_items = with_mutex all_items_mutex (fun () -> !all_items) in
		let last_query = with_mutex query_mutex (fun () -> !last_query) in
		let last_query = String.lowercase_ascii last_query in
		let max_recall = 2000 in
		let max_display = 20 in

		(* collect max_recall matches *)
		let recalled = let rec loop n items =
			if n < 1 then [] else match items with
				| [] -> []
				| item :: tail ->
					match Search.score last_query item with
						| Some (score, indexes) -> {result_source = item; result_score = score; match_indexes = indexes} :: (loop (n-1) tail)
						| None -> loop n tail
			in
			loop max_recall all_items
		in

		(* after grabbing the first `max_recall` matches by length, score them in descending order *)
		let ordered = List.stable_sort (fun a b -> compare (b.result_score) (a.result_score)) recalled in
		with_mutex shown_items_mutex (fun () ->
			shown_items := list_take max_display ordered;

			debug "redraw! %d items of %d" (List.length !shown_items) (List.length all_items);
			flush stdout;
			selected_index := Option.default (match reason, !selected_index with
				| New_query, _ -> None
				| _, 0 -> None
				| New_input, i ->
					(* maintain selection if possible (but only when selected_index>0) *)
					let id = (get_selected_item ()).result_source.input_index in
					findi !shown_items (fun entry -> entry.result_source.input_index = id)
			) 0
		);
		with_ui (Gselui.results_changed)
	in

	let query_changed = fun text ->
		with_mutex query_mutex (fun () ->
			last_query := text;
		);
		redraw New_query
	in

	let finish response : unit =
		source#respond response;
		with_ui (Gselui.hide)
	in

	let selection_made () =
		if !shown_items = [] then () else begin
			let {result_source=entry;_} = get_selected_item () in
			debug "selected item[%d]: %s" entry.input_index entry.text;
			let text = if opts.print_index
				then string_of_int entry.input_index
				else entry.text
			in
			finish (Success text)
		end
	in

	let terminate () = exit Cancelled in
	let iter fn =
		with_mutex shown_items_mutex (fun () ->
			List.iter (fun item ->
				fn (markup item.result_source.text item.match_indexes)
			) !shown_items;
			!selected_index
		)
	in

	let ui = Gselui.show ~query_changed ~iter ~selection_changed ~selection_made ~terminate () in
	ui_ := Some ui;

	(
		init_background_thread ();
		let input_complete = ref false in
		debug "input thread running";
		(* prioritize GUI setup over input processing *)
		let (_, _, _) = Unix.select [] [] [] 0.2 in

		(* input_loop can only mutate state via the stuff we pass it, so
		* make sure everything here is thread-safe *)
		let modify_all_items =
			let last_redraw = ref (Unix.time ()) in
			fun fn -> (
				with_mutex all_items_mutex (fun () -> all_items := fn !all_items);
				let current_time = Unix.time () in
				if (current_time -. !last_redraw) > 0.5 then (
					debug "redrawing";
					last_redraw := current_time;
					redraw New_input
				)
			)
		in

		let append_query text : unit =
			let query = with_mutex query_mutex (fun () ->
				let query = !last_query ^ text in
				last_query := query;
				query
			) in
			Gselui.set_query ui query;
			redraw New_query
		in

		let () =
			try input_loop ~source ~append_query ~modify_all_items ~finish ();
			with e -> prerr_string (Printexc.to_string e)
		in
		debug "input loop complete";
		input_complete := true;
		redraw New_input;
		Gselui.wait ui
	)
;;

let gui_loop ~server ~opts () =
	match server with
		| Some server -> begin
				let display_state = ref None in
				while true do
					let source : source = server#accept in
					try (
						match source#read_options_header with
							| None -> () (* connection closed; ignore *)
							| Some opts ->
									debug "received serialized opts: %s" opts;
									let opts = run_options_of_sexp (Sexp.of_string opts) in
									let () = match !display_state with
										| Some display_state -> display_state
										| None ->
												(* XXX this is a bit hacky... We're just adopting $DISPLAY
												 * from the first client that connects... *)
												Option.may opts.display_env (Unix.putenv "DISPLAY")
									in
									let (_:Thread.t) = Thread.create (fun () ->
										init_background_thread ();
										gui_inner
											~source ~opts
											~exit:(fun _response ->
												debug "session ended"
											) ()
									) () in
									()
					) with e -> (
						let desc = Printexc.to_string e in
						debug "Killing client: %s" desc;
						try (source#respond (Error desc)) with _ -> ()
					)
				done
			end
		| None -> begin
				with_tty (fun tty ->
					gui_inner
						~source:(terminal_source ~tty opts)
						~opts:opts.run_options
						~exit:(fun response ->
							Pervasives.exit (match response with Success _ -> 0 | Cancelled | Error _ -> 1)
						) ()
				)
		end
;;

external fd_of_int : int -> Unix.file_descr = "%identity"
let systemd_first_fd = fd_of_int 3

let main (): unit =
	init_logging ();
	let opts = parse_args () in

	let server = ref None in
	let () = match opts.program_mode with
		| GSEL_CLIENT -> Option.may (Gsel_client.run opts) exit
		| GSEL_STANDALONE -> ()
		| GSEL_SERVER ->
				let fd = if (
					try int_of_string (Unix.getenv "LISTEN_PID") == Unix.getpid ()
					with Not_found -> false
				) then (
					(* socket activation *)
					debug "Using socket activation...";
					let fd_count = int_of_string (Unix.getenv "LISTEN_FDS") in
					if fd_count == 1
						then systemd_first_fd
						else failwith (Printf.sprintf "Expected 1 $LISTEN_FDS, got %d" fd_count)
				) else (
					let fd, path, addr = init_socket opts in
					Unix.bind fd addr;
					Printf.eprintf "Server listening on %s\n" path;
					fd
				) in
				Unix.listen fd 1;
				server := Some (new server fd)
	in
	gui_loop ~server:!server ~opts ()


