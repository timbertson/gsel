open Ctypes
open Foreign

let from = (let open Dl in dlopen ~filename:"libgselui.so" ~flags:[RTLD_NOW; RTLD_LOCAL])

type state = {
	query_changed : string -> unit;
	selection_changed : int -> unit;
	selection_made : unit -> unit;
}

(* Storing state ensures that callbacks are not garbage collected
 * for the duration of the GUI
 *)
let state : state option ref = ref None

let initialize =
	let noop () = () in
	let fn = ref noop in
	let initialize =
		fn := noop;
		foreign ~from "gsel_initialize" (void @-> returning void) in
	fn := initialize;
	fun () -> !fn ()

let hide =
	let hide = foreign ~from "gsel_hide" (void @-> returning void) in
	fun () ->
		hide ();
		state := None

let string_fn = string @-> returning void
let int_fn = int @-> returning void
let void_fn = void @-> returning void
let show =
	let show = foreign ~from "gsel_show"
		(funptr string_fn @-> funptr int_fn @-> funptr void_fn @-> returning void)
	in
	fun ~query_changed ~selection_changed ~selection_made () ->
		initialize ();
		let newstate = Some { query_changed; selection_changed; selection_made } in
		state := (match !state with
			| None -> newstate
			| Some _ -> hide (); newstate
		);
		show query_changed selection_changed selection_made

let set_query = foreign "gsel_set_query" (string @-> returning void)

(* let set_selection = foreign "gsel_set_selection" (int @-> returning void) *)

let set_results : string list -> int -> unit =
	let set = foreign "gsel_set_results" (int @-> ptr string @-> int @-> returning void) in
	fun results idx ->
		let len = List.length results in
		let arr = (CArray.of_list string results) in
		set len (CArray.start arr) idx
