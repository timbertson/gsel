(* local modules *)
open Log
open Search

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

let rgb a b c = `RGB (a lsl 8, b lsl 8, c lsl 8)
let grey l = let l = l lsl 8 in `RGB (l,l,l)
let font_scale = 1204

let rec list_take n lst = if n = 0 then [] else match lst with
	| x::xs -> x :: list_take (n-1) xs
	| [] -> []

let markup_escape = Glib.Markup.escape_text

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

let input_loop ~modify_all_items ~quit () =
	if Unix.isatty Unix.stdin then (
		(* XXX set gui message? *)
		prerr_endline "WARN: stdin is a terminal"
	);
	let i = ref 0 in
	let nonempty_line = ref false in
	let rec loop () =
		let line = try Some (input_line stdin) with End_of_file -> None in
		match line with
			| Some line ->
				if not !nonempty_line && String.length line > 0 then
					nonempty_line := true
				;
				modify_all_items (fun all_items ->
					SortedSet.add all_items {
						text=line;
						match_text=String.lowercase line;
						input_index=(!i);
					}
				);
				i := !i+1;
				loop ()
			| None -> (debug "stdin complete"; ())
	in
	loop ();
	if not !nonempty_line then (
		prerr_endline "No input received";
		quit 1
	)
;;


let main (): unit =
	let () = enable_debug := try Unix.getenv "GSEL_DEBUG" = "1" with Not_found -> false in

	let print_index = ref false in

	(* parse args *)
	let rec process_args args = match args with
		| [] -> ()
		| "-h" :: args
		| "--help" :: args ->
				prerr_string (
					"Usage: gsel [OPTIONS]\n"^
					"\n"^
					"Options:\n"^
					"  --index:   Print out the index (input line number)\n"^
					"             of the selected option, rather than its contents\n"^
					""
				);
				exit 0
		| "--index" :: args ->
				print_index := true;
				process_args args
		| unknown :: _ -> failwith ("Unknown argument: " ^ unknown)
	in
	process_args (List.tl (Array.to_list Sys.argv));


	ignore (GMain.init ());

	let colormap = Gdk.Color.get_system_colormap () in
	let text_color = Gdk.Color.alloc ~colormap (grey 210) in

	let window = GWindow.dialog
		~border_width: 10
		~screen:(Gdk.Screen.default ())
		~width: 600
		~height: 500 (* XXX set window height based on size of entries *)
		~decorated: false
		~show:false
		~modal:false
		~destroy_with_parent:true
		~position: `CENTER_ON_PARENT
		~allow_grow:true
		~allow_shrink:true
		~focus_on_map:true
		~title:"gsel"
		() in

	let active_window = Wnck.currently_active_window () in
	let quit ?event status : unit =
		let () = match event with
			| None ->
				debug "No previous window to activate"
			| Some event ->
				let timestamp = (GdkEvent.get_time event) in
				debug "Activating old xid: %ld @ timestamp %ld" active_window timestamp;
				Wnck.activate_xid active_window timestamp;
		in
		window#destroy ();
		exit status
	in

	(* Nobody likes you, action area *)
	window#action_area#destroy ();

	(* adopt the vbox as out main content area *)
	(* let vbox = GPack.vbox ~spacing: 10 ~packing:window#add () in *)
	let vbox = window#vbox in
	vbox#set_spacing 10;

	(* using two extra boxes seems a rather hacky way of getting some padding... *)
	let input_box = GBin.event_box ~packing:vbox#pack ~border_width:0 () in
	let input_box_inner = GBin.event_box ~packing:input_box#add ~border_width:6 () in
	let input = GEdit.entry ~activates_default:true ~packing:input_box_inner#add () in
	input#set_has_frame false;
	let columns = new GTree.column_list in
	let column = columns#add Gobject.Data.string in
	let list_store = GTree.list_store columns in
	let tree_view = GTree.view
		~model:list_store
		~border_width:0
		~show:true
		~enable_search:false
		~packing:(vbox#pack ~expand:true) () in
	(* TODO: ellipsize *)
	let column_view = GTree.view_column
		~renderer:((GTree.cell_renderer_text [
			`FOREGROUND_GDK text_color;
			`SIZE_POINTS 12.0;
			`YPAD 5;
		]), [("markup", column)]) () in
	ignore (tree_view#append_column (column_view));
	tree_view#set_headers_visible false;
	let tree_selection = tree_view#selection in

	let all_items = ref (SortedSet.create ()) in
	let shown_items = ref [] in
	let last_query = ref "" in
	let selected_index = ref 0 in

	let with_mutex : (unit -> unit) -> unit =
		let m = Mutex.create () in
		fun fn ->
			Mutex.lock m;
			let () = try fn ()
				with e -> (Mutex.unlock m; raise e) in
			Mutex.unlock m
	in


	ignore (tree_selection#connect#changed ~callback:(fun () ->
		List.iter (fun path ->
			match GTree.Path.get_indices path with
				| [|i|] ->
					debug "selected index is now %d" i;
					selected_index := i
				| _ -> assert false
		) tree_selection#get_selected_rows
	));

	let clear_selection () =
		selected_index := 0;
		tree_selection#unselect_all ()
	in

	let set_selection idx =
		selected_index := idx;
		tree_selection#select_path (GTree.Path.create [idx])
	in

	let shift_selection direction =
		let new_idx = !selected_index + direction in
		if new_idx < 0 || new_idx >= (List.length !shown_items) then
			debug "ignoring shift_selection"
		else
			set_selection new_idx
	in

	let redraw () =
		list_store#clear ();
		let max_recall = 2000 in
		let max_display = 20 in

		(* collect max_recall matches *)
		let recalled = let rec loop n items =
			if n < 1 then [] else match items with
				| [] -> []
				| item :: tail ->
					match Search.score !last_query item with
						| Some (score, indexes) -> {result_source = item; result_score = score; match_indexes = indexes} :: (loop (n-1) tail)
						| None -> loop n tail
			in
			loop max_recall !all_items
		in

		(* after grabbing the first `max_recall` matches by length, score them in descending order *)
		let ordered = List.stable_sort (fun a b -> compare (b.result_score) (a.result_score)) recalled in
		shown_items := list_take max_display ordered;

		debug "redraw! %d items of %d" (List.length !shown_items) (List.length !all_items);
		flush stdout;
		(* TODO: overwrite text, rather than always recreating each item? *)
		let rec loop i entries =
			match entries with
				| [] -> ()
				| result :: tail ->
					let added = list_store#append () in
					list_store#set ~row:added ~column (markup result.result_source.text result.match_indexes);
					let i = i - 1 in
					if i > 0 then loop i tail else ()
		in
		loop max_display !shown_items;
		if !shown_items = [] then (
			clear_selection ()
		) else
			(* XXX do something smart to track the content of the selected item,
			 * rather than just maintaining the selected index *)
			set_selection !selected_index
	in

	let update_query = fun text ->
		last_query := String.lowercase text;
		redraw ()
	in

	ignore (input#connect#notify_text update_query);

	let selection_made ?event () =
		let selected = try Some (List.nth !shown_items !selected_index) with Failure _ -> None in
		begin match selected with
			| Some {result_source=entry;_} ->
					let text = if !print_index
						then string_of_int entry.input_index
						else entry.text
					in
					print_endline text;
					quit ?event 0
			| None -> ()
		end
	in

	let is_ctrl evt = GdkEvent.Key.state evt = [`CONTROL] in
	(* why are this different to GdkKeysyms._J/_K ? *)
	let (ctrl_j, _) = GtkData.AccelGroup.parse "<Ctrl>j" in
	let (ctrl_k, _) = GtkData.AccelGroup.parse "<Ctrl>k" in

	ignore (window#event#connect#key_press (fun event ->
		let key = GdkEvent.Key.keyval event in
		debug "Key: %d" key;
		let module K = GdkKeysyms in
		match key with
			|k when k=K._Escape -> quit ~event 1; true
			|k when k=K._Return -> selection_made ~event (); true
			|k when k=K._Up -> shift_selection (-1); true
			|k when k=K._Down -> shift_selection 1; true
			|k when k=K._Page_Up -> set_selection 0; true
			|k when k=K._Page_Down -> set_selection (max 0 ((List.length !shown_items) - 1)); true
			| _ ->
				if is_ctrl event then match key with
					| k when k = ctrl_j -> shift_selection 1; true
					| k when k = ctrl_k -> shift_selection (-1); true
					| _ -> false
				else false
	));
	ignore (tree_view#connect#row_activated (fun _ _ -> selection_made ()));
	ignore (window#event#connect#delete (fun _ -> quit 1; true));
	(* XXX set always-on-top *)
	window#set_skip_taskbar_hint true;
	(* window#set_skip_pager_hint true; *)

	(* stylings! *)
	(* let all_states col = [ *)
	(* 	`INSENSITIVE, col; *)
	(* 	`NORMAL, col; *)
	(* 	`PRELIGHT, col; *)
	(* 	`SELECTED, col; *)
	(* ] *)


	let input_bg = grey 40 in

	let ops = new GObj.misc_ops window#as_widget in
	ops#modify_bg [`NORMAL, grey 10];

	let ops = new GObj.misc_ops vbox#as_widget in
	ops#modify_bg [`NORMAL, grey 100];

	let ops = new GObj.misc_ops tree_view#as_widget in
	ops#modify_base [`NORMAL, grey 25];
	(* let selected_bg = rgb 37 89 134 in (* #255986 *) *)
	(* let selected_bg = rgb 70 137 196 in (* #4689C4 *) *)
	let selected_bg = rgb 61 85 106 in (* #3D556A *)
	let selected_fg = rgb 255 255 255 in
	ops#modify_base [
		`SELECTED, selected_bg;
		`ACTIVE, selected_bg;
	];

	ops#modify_text [
		`SELECTED, selected_fg;
		`ACTIVE, selected_fg;
	];

	let ops = new GObj.misc_ops input_box#as_widget in
	ops#modify_bg [`NORMAL, input_bg];

	let ops = new GObj.misc_ops input#as_widget in
	let font = ops#pango_context#font_description in
	Pango.Font.modify font ~weight:`BOLD ~size:(10 * font_scale) ();
	ops#modify_font font;
	ops#modify_base [`NORMAL, input_bg];
	ops#modify_text [`NORMAL, grey 250];


	window#show ();
	let () = match active_window with
		| 0l -> ()
		| xid ->
			debug "setting transient for X window %ld" xid;
			let parent_win = (Gdk.Window.create_foreign xid) in
			(* NOTE: this segfaults if we try to do it before window#show *)
			let gdk_win = GtkBase.Widget.window (window#as_window) in
			Gdk.Window.set_transient_for gdk_win parent_win
	in

	let input_complete = ref false in
	let (_:Thread.t) = Thread.create (fun () ->
		(* block these signals so that they are delivered to the main thread *)
		let (_:int list) = Thread.sigmask Unix.SIG_BLOCK [Sys.sigint] in

		(* input_loop can only mutate state via the stuff we pass it, so
		 * make sure everything here is thread-safe *)
		let modify_all_items fn = with_mutex (fun () ->
			all_items := fn !all_items
		) in
		let quit = GtkThread.sync (quit ?event:None) in
		input_loop ~modify_all_items ~quit ();
		input_complete := true;
		GtkThread.sync redraw ();
	) () in

	(* install periodic redraw handler, which loops until input_loop is done *)
	let (_:GMain.Timeout.id) = GMain.Timeout.add ~ms:500 ~callback:(fun () ->
		if not !input_complete
			then (debug "redraw (timer)"; redraw (); true)
			else false
	) in

	GMain.main ()
