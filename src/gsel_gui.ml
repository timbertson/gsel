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

let markup_escape =
	let amp = Str.regexp "&" in
	let special = Str.regexp "[<>]" in
	fun s -> s
		|> Str.global_replace amp "&amp;"
		|> Str.global_substitute special (function
			| ">" -> "&gt;"
			| "<" -> "&lt;"
			| _ -> failwith "impossible"
		)

type displayed_items = {
	items: search_result list;
	selected_index: int;
}

let markup str indexes =
	let open Search.Highlight in
	let parts = Search.highlight str indexes in
	let parts = List.map (function
		(* XXX define a style somewhere or use programmatic style attributes rather than
		 * building ugly html strings *)
		| Highlighted s -> "<span color=\"#ffffff\" weight=\"bold\" underline=\"low\" underline_color=\"#dddddd\">" ^ markup_escape s ^ "</span>"
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

module Shared : sig
	type 'a t
	val init : ('a ref) -> 'a t
	val read : 'a t -> 'a
	val update : ('a -> 'a) -> 'a t -> unit
	val mutate : ('a ref -> 'r) -> 'a t -> 'r
	val mutate_full : (Mutex.t -> 'a ref -> 'r) -> 'a t -> 'r
end = struct
	type 'a t = Mutex.t * 'a ref
	let init item = (Mutex.create (), item)
	let mutate_full fn (m, var) =
		Mutex.lock m;
		let rv = try fn m var
			with e -> (Mutex.unlock m; raise e) in
		Mutex.unlock m;
		rv
	let mutate fn = mutate_full (fun _ r -> fn r)
	let update fn = mutate (fun r -> r := fn !r)
	let read v = mutate (!) v
end

type redraw_state = {
	dirty : bool;
	modified : Condition.t;
	terminated : bool;
}

let string_of_redraw_state { dirty; terminated } =
	Printf.sprintf "{ dirty=%b; terminated=%b }" dirty terminated

exception Thread_end

let gui_inner ~source ~opts ~exit () =
	debug "gui running from source: %s" source#repr;
	let get_selected_item { items; selected_index } =
		try Some (List.nth items selected_index)
		with Failure _ -> None
	in

	let all_items = Shared.init (ref (SortedSet.create ())) in
	let displayed_items = Shared.init (ref { items = []; selected_index = 0 }) in
	let last_query = Shared.init (ref "") in

	let selection_changed i =
		debug "selected index is now %d" i;
		displayed_items |> Shared.update (fun shown ->
			let max_idx = (List.length shown.items) - 1 in
			{ shown with
				selected_index = (min i max_idx);
			}
		)
	in

	let ui_ = ref None in
	let with_ui fn =
		match !ui_ with
			| Some ui -> fn ui
			| None -> ()
	in

	let redraw_state = Shared.init (ref {
		dirty = false;
		modified = Condition.create ();
		terminated = false;
	}) in

	let force_redraw ?state () =
		let update = (fun state ->
			with_ui (Gselui.results_changed);
			{ state with dirty = false }
		) in
		match state with
			| Some state -> state := update !state (* mutex held *)
			| None -> redraw_state |> Shared.update update
	in

	let mark_dirty () =
		redraw_state |> Shared.update (fun state ->
			Condition.signal state.modified;
			{ state with dirty = true }
		)
	in

	let terminate_redraw_thread () =
		redraw_state |> Shared.update (fun state ->
			debug "signalling termination of redraw thread";
			Condition.signal state.modified;
			{ state with terminated = true }
		)
	in

	let (_:Thread.t) = Thread.create (fun () ->
		init_background_thread ();
		let check_alive state =
			if !state.terminated then raise Thread_end in
		try
			while true do
				redraw_state |> Shared.mutate_full (fun mutex state ->
					let { modified; dirty } = !state in
					check_alive state;
					if dirty then force_redraw ~state ();
					Condition.wait modified mutex;
					check_alive state;
				);
				(* (* debounce - collect redraws for 1/4 second after touch *) *)
				let (_, _, _) = Unix.select [] [] [] 0.25 in
				()
			done;
		with Thread_end -> debug "redraw loop terminated"
	) () in

	let redraw reason =
		let all_items = Shared.read all_items in
		let last_query = Shared.read last_query in
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
		displayed_items |> Shared.update (fun displayed_items ->
			let items = list_take max_display ordered in
			let selected_index = Option.default 0 (match reason, displayed_items.selected_index with
				| New_query, _ -> None
				| _, 0 -> None
				| New_input, i ->
					(* maintain selection if possible (but only when selected_index>0) *)
					get_selected_item (displayed_items) |> Option.bind (fun item ->
						let id = item.result_source.input_index in
						let matcher = (fun entry -> entry.result_source.input_index = id) in
						findi displayed_items.items matcher
					)
			) in

			debug "redraw! %d items of %d" (List.length displayed_items.items) (List.length all_items);
			flush stdout;
			{ items; selected_index }
		);
		match reason with
			| New_query -> force_redraw ()
			| New_input -> mark_dirty () (* this happens a lot, do debounce redraws *)
	in

	let query_changed : string -> unit = fun text ->
		last_query |> Shared.update (fun _ -> text);
		redraw New_query
	in

	let finish response : unit =
		(* this will be called exactly once. If invoked by the GUI,
		 * Gselui.hide() will have no effect *)
		debug "finish() invoked";
		source#respond response;
		terminate_redraw_thread ();
		debug "exiting";
		exit response
	in

	let completed selection_accepted =
		debug "completed - selection_accepted = %b" selection_accepted;
		if selection_accepted then (
			let displayed_items = displayed_items |> Shared.read in
			match get_selected_item displayed_items with
				| Some {result_source=entry;_} ->
					debug "selected item[%d]: %s" entry.input_index entry.text;
					let text = if opts.print_index
						then string_of_int entry.input_index
						else entry.text
					in
					finish (Success text)
				| None -> ()
		) else finish Cancelled
	in

	let iter fn =
		let displayed_items = displayed_items |> Shared.read in
		List.iter (fun item ->
			fn (markup item.result_source.text item.match_indexes)
		) displayed_items.items;
		displayed_items.selected_index
	in

	let ui = Gselui.show ~query_changed ~iter ~selection_changed ~completed () in
	ui_ := Some ui;

	(
		init_background_thread ();
		let input_complete = ref false in
		debug "input thread running";
		(* prioritize GUI setup over input processing *)
		let (_, _, _) = Unix.select [] [] [] 0.1 in

		let modify_all_items fn =
			all_items |> Shared.update fn;
			redraw New_input
		in

		let append_query text : unit =
			let query = last_query |> Shared.mutate (fun last_query ->
				let query = !last_query ^ text in
				last_query := query;
				query
			) in
			Gselui.set_query ui query;
			redraw New_query
		in

		let () =
			let finish response =
				(* if the input_loop triggers finish,
				 * make sure the GUI ends *)
				with_ui (Gselui.hide);
				finish response
			in
			try input_loop ~source ~append_query ~modify_all_items ~finish ();
			with e -> prerr_string (Printexc.to_string e)
		in
		debug "input loop complete";
		input_complete := true;
		redraw New_input;
		Gselui.wait ui;
		debug "Gselui thread ended"
	)
;;

let gui_loop ~server ~opts () =
	match server with
		| Some server -> begin
				let display_state = ref None in
				while true do
					let source : source = server#accept in
					debug "accepted new connection";
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
												opts.display_env |> Option.may (Unix.putenv "DISPLAY")
									in
									let (_:Thread.t) = Thread.create (fun () ->
										init_background_thread ();
										gui_inner
											~source ~opts
											~exit:(fun _response ->
												debug "client session ended"
											) ();
											debug "gui_inner terminated\n\n\n\n"
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
							debug "exiting";
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
		| GSEL_CLIENT -> (Gsel_client.run opts) |> Option.may exit
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


