open Lwt

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

let all_states col = [
	`INSENSITIVE, col;
	`NORMAL, col;
	`PRELIGHT, col;
	`SELECTED, col;
]

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
	Lwt_glib.install ();

	let gui_end, wakener = Lwt.wait () in

	let colormap = Gdk.Color.get_system_colormap () in
	let text_color = Gdk.Color.alloc ~colormap (grey 210) in

	let window = GWindow.window
		~border_width: 10
		~screen:(Gdk.Screen.default ())
		~width: 600
		~height: 500 (* XXX set window height based on size of entries *)
		~decorated: false
		~position: `CENTER
		~allow_grow:true
		~allow_shrink:true
		~title:"gsel"
		() in

	let quit status : unit =
		(* window#destroy; *)
		Lwt.wakeup wakener ();
		exit status
		(* () *)
	in

	let vbox = GPack.vbox ~spacing: 10 ~packing:window#add () in

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

	ignore (tree_selection#connect#changed ~callback:(fun () ->
		List.iter (fun path ->
			match GTree.Path.get_indices path with
				| [|i|] ->
					debug "selected index is now %d" i;
					selected_index := i
				| _ -> assert false
		) tree_selection#get_selected_rows
	));

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

		(* after grabbing the first 100 matches by length, score them in descending order *)
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
		loop max_display !shown_items
	in

	let update_query = fun text ->
		last_query := String.lowercase text;
		redraw ()
	in

	let input_loop =
		let redraw () = redraw (); return_unit in
		let read_loop =
			let lines = Lwt_io.read_lines Lwt_io.stdin in
			let i = ref 0 in
			Lwt_stream.iter (fun line ->
				all_items := SortedSet.add !all_items {
					text=line;
					match_text=String.lowercase line;
					input_index=(!i);
				};
				i := !i+1;
			) lines
		in
		let update_loop =
			lwt () = Lwt_unix.sleep 0.5 in
			redraw ()
		in
		Lwt.pick [read_loop; update_loop] >>= redraw
	in

	ignore (input#connect#notify_text update_query);

	let selection_made () =
		let selected = try Some (List.nth !shown_items !selected_index) with Failure _ -> None in
		begin match selected with
			| Some {result_source=entry;_} ->
					let text = if !print_index
						then string_of_int entry.input_index
						else entry.text
					in
					print_endline text;
					quit 0
			| None -> ()
		end
	in

	(* XXX are there constants, or do we really have to parse thse at runtime? *)
	let (esc, _) = GtkData.AccelGroup.parse "Escape" in
	let (ret, _) = GtkData.AccelGroup.parse "Return" in
	ignore (window#event#connect#key_release (fun evt ->
		let key = GdkEvent.Key.keyval evt in
		debug "Key: %d" key;
		let () = match key with
			|k when k=esc -> quit 1
			|k when k=ret -> selection_made ()
			| _ -> ()
		in
		true
	));
	ignore (tree_view#connect#row_activated (fun _ _ -> selection_made ()));
	ignore (window#event#connect#delete (fun _ -> quit 1; true));
	(* XXX set always-on-top *)
	window#set_skip_taskbar_hint true;
	(* window#set_skip_pager_hint true; *)
	(* button#connect#clicked ~callback:(fun () -> prerr_endline "Hello World"); *)
	(* button#connect#clicked ~callback:window#destroy; *)

	(* stylings! *)
	let input_bg = grey 40 in

	let ops = new GObj.misc_ops window#as_widget in
	ops#modify_bg [`NORMAL, grey 10];

	let ops = new GObj.misc_ops vbox#as_widget in
	ops#modify_bg [`NORMAL, grey 100];

	let ops = new GObj.misc_ops tree_view#as_widget in
	ops#modify_base [`NORMAL, grey 25];
	ops#modify_base [`SELECTED, rgb 37 89 134];

	let ops = new GObj.misc_ops input_box#as_widget in
	ops#modify_bg [`NORMAL, input_bg];

	let ops = new GObj.misc_ops input#as_widget in
	let font = ops#pango_context#font_description in
	Pango.Font.modify font ~weight:`BOLD ~size:(10 * font_scale) ();
	ops#modify_font font;
	ops#modify_base [`NORMAL, input_bg];
	ops#modify_text [`NORMAL, grey 250];


	window#show ();

	Lwt_main.run (Lwt.join [
		gui_end;
		input_loop;
	]);
	debug "ALL DONE"
