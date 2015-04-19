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

let rgb a b c = `RGB (a lsl 8, b lsl 8, c lsl 8)
let grey l = let l = l lsl 8 in `RGB (l,l,l)
let font_scale = 1204

type redraw_reason = New_input | New_query

let ignore_signal (s:GtkSignal.id) = ignore s


class server fd = object
	method accept =
		let stream, _addr = Unix.accept fd in
		new stream_input stream
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

let run_client fd =
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
	exit status
;;


let input_loop ~source ~modify_all_items ~finish () =
	let i = ref 0 in
	let nonempty_line = ref false in

	let max_items = try int_of_string (Unix.getenv "GSEL_MAX_ITEMS") with Not_found -> 10000 in
	let rec loop () =
		match source#read_line with
			| Some line ->
				if not !nonempty_line && String.length line > 0 then
					nonempty_line := true
				;
				debug "item[%d]: %s" !i line;
				modify_all_items (fun all_items ->
					SortedSet.add all_items {
						text=line;
						match_text=String.lowercase line;
						input_index=(!i);
					}
				);
				i := !i+1;

				(* give UI a chance to keep up *)
				if ((!i mod 500) = 0) then (
					Thread.delay 0.1
				);

				if (!i = max_items) then (
					debug "capping items at %d" max_items
				) else (
					loop ()
				)
			| None -> (debug "input complete"; ())
	in
	loop ();
	if not !nonempty_line then (
		finish (Error "No input received");
	)
;;

type xlib = {
	display: Xlib.display;
	activate: Xlib.window -> unit;
	get_toplevel: Xlib.window -> Xlib.window;
}

let init_xlib () =
	let open Xlib in
	let display = open_display () in
	let wm_state = xInternAtom display "WM_STATE" false in

	let activate win =
		let xid = xid_of_window win in
		debug "Activating window %d" xid;

		(* let xid = Int32.of_int xid in *)
		(* let parent_win = (Gdk.Window.create_foreign (Gdk.Window.native_of_xid xid)) in *)
		(* XXX None of these work :/ *)
		(* let () = Gdk.Window.focus parent_win (Int32.of_int 0) in *)
		(* let () = Gdk.Window.focus parent_win (GMain.Event.get_current_time ()) in *)

		(* Instead, we need to use xlib directly *)
		let activateWindow = xInternAtom display "_NET_ACTIVE_WINDOW" false in
		let serial = xLastKnownRequestProcessed display in
		let screen = xDefaultScreenOfDisplay display in
		xSendEvent ~dpy:display ~win:(xRootWindowOfScreen screen)
			~propagate:false ~event_mask:SubstructureNotifyMask
			(XClientMessageEvCnt {
				client_message_send_event = true;
				client_message_display = display;
				client_message_window = win;
				client_message_type = activateWindow;
				client_message_serial = serial;
				client_message_data = ClientMessageLongs [|
					1; (* source = app *)
					Int32.to_int (GMain.Event.get_current_time ());
					0; 0; 0;
				|];
			});
		(* after giving window input, make sure it's also on top *)
		xRaiseWindow display win;
		(* wait for all the X stuff to finish *)
		xSync display false;
	in

	let rec get_toplevel win =
		(* XXX should be able to get the focus window directly via _NET_ACTIVE_WINDOW,
		* rather than `get_toplevel` hackery *)
		(* let root = xRootWindowOfScreen screen in *)
		(* let (_actual_type, _fmt, _n, _bytes, pw) = xGetWindowProperty_window *)
		(* 	display root wm_state *)
		(* 	0 0 false AnyPropertyType in *)
		(* parent_window := Some pw; *)

		let root, parent, _children = xQueryTree display win in
		debug "window 0x%x has parent 0x%x (root = 0x%x). WM_STATE ? %b"
			(xid_of_window win)
			(xid_of_window parent)
			(xid_of_window root)
			(hasWindowProperty display win wm_state)
			;
			(* If we find a window with WM_STATE property set, stop there.
			* Otherwise, hope that the toplevel window is the one directly
			* below the root *)
		if root == parent || hasWindowProperty display win wm_state then win else get_toplevel parent
	in
	{ activate = activate; get_toplevel = get_toplevel; display = display }
;;

let gui_inner ~source ~colormap ~text_color ~opts ~xlib ~exit () =
	let window = GWindow.dialog
		~border_width: 10
		~screen:(Gdk.Screen.default ())
		~width: 600
		~height: 500 (* XXX set window height based on size of entries *)
		~decorated: false
		~show:false
		~modal:true
		~destroy_with_parent:true
		~position: `CENTER_ON_PARENT
		~allow_grow:true
		~allow_shrink:true
		(* XXX doesn't seem to do what I'd expect it to ... *)
		~focus_on_map:true
		~title:"gsel"
		() in

	window#set_skip_taskbar_hint true;
	window#set_keep_above true;

	(* let active_window = Wnck.currently_active_window () in *)

	let parent_window = ref None in

	let finish ?event response : unit =
		source#respond response;

		let () = match (event, !parent_window) with
			| None ,_ | _, None -> exit response
			| Some event, Some parent_window ->
				ignore_signal (window#connect#after#destroy (fun event ->
					(* "after remove" seems to trigger before the window is
					* actually, you know, destroyed. So we add an idle action which
					* hopefully only fires _after_ the window is actually
					* gone. If we activate the parent window too soon,
					* the window manager might override that decision when
					* our window dies
					*)

					ignore (GMain.Idle.add (fun () ->
						xlib.activate parent_window;
						exit response;
						false
					)
				);
				()
			));
			()
		in
		window#destroy ()
	in

	(* Nobody likes you, action area *)
	window#action_area#destroy ();

	(* adopt the vbox as our main content area *)
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
	let get_selected_item () = List.nth !shown_items !selected_index in

	let with_mutex : (unit -> unit) -> unit =
		let m = Mutex.create () in
		fun fn ->
			Mutex.lock m;
			let () = try fn ()
				with e -> (Mutex.unlock m; raise e) in
			Mutex.unlock m
	in


	let update_current_selection i =
		debug "selected index is now %d" i;
		selected_index := i
	in

	ignore_signal (tree_selection#connect#changed ~callback:(fun () ->
		List.iter (fun path ->
			match GTree.Path.get_indices path with
				| [|i|] -> update_current_selection i
				| _ -> assert false
		) tree_selection#get_selected_rows
	));

	let set_selection idx =
		debug "Setting selection to %d" idx;
		update_current_selection idx;
		tree_selection#select_path (GTree.Path.create [idx])
	in

	let clear_selection () =
		if !shown_items = [] then (
			selected_index := 0;
			tree_selection#unselect_all ()
		) else (
			set_selection 0
		)
	in

	let shift_selection direction =
		let new_idx = !selected_index + direction in
		if new_idx < 0 || new_idx >= (List.length !shown_items) then
			debug "ignoring shift_selection"
		else
			set_selection new_idx
	in

	let redraw reason =
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
		let updated_idx = match reason, !selected_index with
			| New_query, _ -> None
			| _, 0 -> None
			| New_input, i ->
				(* maintain selection if possible (but only when selected_index>0) *)
				let id = (get_selected_item ()).result_source.input_index in
				findi !shown_items (fun entry -> entry.result_source.input_index = id)
		in
		match updated_idx with
			| Some i -> set_selection i
			| None -> clear_selection ()
	in

	let update_query = fun text ->
		last_query := String.lowercase text;
		redraw New_query
	in

	ignore_signal (input#connect#notify_text update_query);

	let selection_made ?event () =
		if !shown_items = [] then () else begin
			let {result_source=entry;_} = get_selected_item () in
			debug "selected item[%d]: %s" entry.input_index entry.text;
			let text = if opts.print_index
				then string_of_int entry.input_index
				else entry.text
			in
			finish ?event (Success text)
		end
	in

	let is_ctrl evt = GdkEvent.Key.state evt = [`CONTROL] in
	(* why are these different to GdkKeysyms._J/_K ? *)
	let (ctrl_j, _) = GtkData.AccelGroup.parse "<Ctrl>j" in
	let (ctrl_k, _) = GtkData.AccelGroup.parse "<Ctrl>k" in

	ignore_signal (window#event#connect#key_press (fun event ->
		let key = GdkEvent.Key.keyval event in
		debug "Key: %d" key;
		let module K = GdkKeysyms in
		match key with
			|k when k=K._Escape -> finish ~event Cancelled; true
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
	ignore_signal (tree_view#connect#row_activated (fun _ _ -> selection_made ()));
	ignore_signal (window#event#connect#delete (fun _ -> finish Cancelled; true));

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

	(* https://blogs.gnome.org/jnelson/2010/10/13/those-realize-map-widget-signals/ *)
	(* window *realize* occurs when the window resource is created *)
	let misc_events = new GObj.misc_signals (window#as_widget) in
	ignore_signal (misc_events#realize (fun event ->
		let open Xlib in
		parent_window := Option.map (xGetInputFocus xlib.display) (fun w ->
			let w = xlib.get_toplevel w in
			parent_window := Some w;
			let xid = xid_of_window w in
			debug "setting transient for %d" xid;
			let xid = Int32.of_int xid in

			let parent_win = (Gdk.Window.create_foreign (Gdk.Window.native_of_xid xid)) in
			(* NOTE: this segfaults if we try to do it before window is realized *)
			let gdk_win = GtkBase.Widget.window (window#as_window) in
			Gdk.Window.set_transient_for gdk_win parent_win;
			w
		);
	));

	(* window *map* occurs when the window is shown. window.focus_on_map
	 * doesn't do what you'd think it would, so we manually activate
	 * our parent window here (using xlib).
	 * Why not activate our _own_ window? We already have a reference to
	 * the parent xwindow, and it's not clear how to get an xwindow
	 * from a gtk one. Since we're modal, it has the same effect.
	 *)
	ignore_signal (window#event#connect#map (fun event ->
		Option.may !parent_window (xlib.activate);
		false
	));

	(* ignore_signal (window#event#connect#expose (fun event -> *)
	(* TODO: grab keyboard? *)
	(* 	true *)
	(* )); *)

	window#present();

	let input_complete = ref false in
	let (_:Thread.t) = Thread.create (fun () ->
		init_background_thread ();
		(* prioritize GUI setup over input processing *)
		let (_, _, _) = Unix.select [] [] [] 0.2 in

		(* input_loop can only mutate state via the stuff we pass it, so
		* make sure everything here is thread-safe *)
		let modify_all_items fn = with_mutex (fun () ->
			all_items := fn !all_items
		) in
		let finish = GtkThread.sync (finish ?event:None) in
		let () =
			try input_loop ~source ~modify_all_items ~finish ();
			with e -> prerr_string (Printexc.to_string e)
		in
		input_complete := true;
		GtkThread.sync redraw New_input;
	) () in

	(* install periodic redraw handler, which loops until input_loop is done *)
	let (_:GMain.Timeout.id) = GMain.Timeout.add ~ms:500 ~callback:(fun () ->
		if not !input_complete
			then (debug "redraw (timer)"; redraw New_input; true)
			else false
	) in
	()
;;

let gui_loop ~server ~opts () =
	ignore (GMain.init ());
	let xlib = init_xlib () in

	let colormap = Gdk.Color.get_system_colormap () in
	let text_color = Gdk.Color.alloc ~colormap (grey 210) in

	match server with
		| Some server -> begin
				let (_:Thread.t) = Thread.create (fun () ->
					(* block these signals so that they are delivered to the main thread *)
					let (_:int list) = Thread.sigmask Unix.SIG_BLOCK [Sys.sigint] in
					while true do
						let source = server#accept in
						match source#read_line with
							| None -> () (* connection closed; ignore *)
							| Some (line:string) ->
									debug "received serialized opts: %s" line;
									let opts = run_options_of_sexp (Sexp.of_string line) in
									GtkThread.sync (gui_inner ~source ~colormap ~text_color ~opts ~xlib ~exit:(fun _response ->
										debug "session ended"
									)) ()
					done
				) () in
				GMain.main ()
			end
		| None -> begin
				if Unix.isatty Unix.stdin then (
					(* XXX set gui message? *)
					prerr_endline "WARN: stdin is a terminal"
				);
				gui_inner ~source:(new stdin_input) ~colormap ~text_color ~opts ~xlib ~exit:(fun response ->
					Pervasives.exit (match response with Success _ -> 0 | Cancelled | Error _ -> 1)
				) ();
				GMain.main ()
		end
;;

let main (): unit =
	init_logging ();
	let opts = parse_args () in

	let server = ref None in
	let () = match opts.program_mode with
		| GSEL_CLIENT -> Option.may (Gsel_client.run opts) exit
		| GSEL_STANDALONE -> ()
		| GSEL_SERVER ->
				let fd, path, addr = init_socket opts in
				Unix.bind fd addr;
				Unix.listen fd 1;
				Printf.eprintf "Server listening on %s\n" path;
				server := Some (new server fd)
	in
	gui_loop ~server:!server ~opts:opts.run_options ()


