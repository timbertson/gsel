open OUnit2

module StringDiff = struct
	type t = string
	let pp_printer fmt str = Format.pp_print_string fmt ("\"" ^ str ^ "\"")
	let compare = compare
	let pp_print_sep fmt () = Format.pp_print_string fmt ", "
end
module StringList = OUnitDiff.ListSimpleMake(StringDiff)

let assert_highlight query input expected =
	let match_text = String.lowercase input in
	let item = Search.({text=input;match_text=match_text}) in
	StringList.assert_equal
		expected
		(Search.highlight query item).Search.result_parts

let () =
	Log.enable_debug := true;
	run_test_tt_main (OUnit2.test_list [
		"highlighting" >:: (fun _ ->
			assert_highlight "16" "123456" [""; "1"; "2345"; "6"; ""];
			assert_highlight "3" "12345" ["12"; "3"; "45"];
			assert_highlight "2" "123" ["1"; "2"; "3"];
		);
	])
