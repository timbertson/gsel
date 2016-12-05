open Ctypes
open Foreign
open Log

let from = (let open Dl in dlopen ~filename:"libgselui.so" ~flags:[RTLD_NOW; RTLD_LOCAL])

type state = {
	query_changed : string -> unit;
	selection_changed : int -> unit;
	completed : bool -> unit;
	iter : (string -> unit ptr -> unit) -> unit ptr -> int;
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

let string_fn = string @-> returning void
let int_fn = int @-> returning void
let void_fn = void @-> returning void
let bool_fn = bool @-> returning void

let closure = ptr void
let string_closure_fn = string @-> closure @-> returning void
let result_iter_fn = funptr string_closure_fn @-> closure @-> returning int

let show =
	let show = foreign ~from "gsel_show" (
		funptr ~runtime_lock: true string_fn
		@-> funptr ~runtime_lock: true result_iter_fn
		@-> funptr ~runtime_lock: true int_fn
		@-> funptr ~runtime_lock: true bool_fn
		@-> returning state_ptr
	) in
	fun ~query_changed ~iter ~selection_changed ~completed () ->
		initialize ();
		let iter = fun fn closure -> iter (fun item -> fn item closure) in
		let ui_state = show query_changed iter selection_changed completed in
		{ query_changed; iter; selection_changed; completed; ui_state }

let set_query =
	let set_query = foreign "gsel_set_query" (state_ptr @-> string @-> returning void) in
	fun state query -> set_query state.ui_state query

let results_changed : state -> unit =
	let update = foreign "gsel_results_changed" (state_ptr @-> returning void) in
	fun state -> update state.ui_state
