open Ctypes
open Foreign
open Log

let from = (let open Dl in dlopen ~filename:"libgselui.so" ~flags:[RTLD_NOW; RTLD_LOCAL])

type state = {
	query_changed : string -> unit;
	selection_changed : int -> unit;
	selection_made : unit -> unit;
	ui_state : unit ptr;
}

let state_ptr = ptr void

let initialize =
	let noop () = () in
	let fn = ref noop in
	let initialize =
		fn := noop;
		foreign ~from "gsel_initialize" (void @-> returning void) in
	fn := initialize;
	fun () -> !fn ()

let hide =
	let hide = foreign ~from "gsel_hide" (state_ptr @-> returning void) in
	fun state -> hide state.ui_state

let wait =
	let wait = foreign ~from "gsel_wait" (state_ptr @-> returning void) in
	fun state -> wait state.ui_state

let string_fn = string @-> returning void
let int_fn = int @-> returning void
let void_fn = void @-> returning void

let show =
	let show = foreign ~from "gsel_show" (
		funptr ~runtime_lock: true string_fn
		@-> funptr ~runtime_lock: true int_fn
		@-> funptr ~runtime_lock: true void_fn
		@-> funptr ~runtime_lock: true void_fn
		@-> returning state_ptr
	) in
	fun ~query_changed ~selection_changed ~selection_made ~terminate () ->
		initialize ();
		let ui_state = show query_changed selection_changed selection_made terminate in
		{ query_changed; selection_changed; selection_made; ui_state }

let set_query =
	let set_query = foreign "gsel_set_query" (state_ptr @-> string @-> returning void) in
	fun state query -> set_query state.ui_state query

let set_results : state -> string list -> int -> unit =
	let set = foreign "gsel_set_results" (state_ptr @-> int @-> ptr string @-> int @-> returning void) in
	fun state results idx ->
		let len = List.length results in
		let arr = (CArray.of_list string results) in
		set state.ui_state len (CArray.start arr) idx
