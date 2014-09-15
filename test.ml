open OUnit2

open Search.Highlight

module StringDiff = struct
	type t = string
	let pp_printer fmt str = Format.pp_print_string fmt ("\"" ^ str ^ "\"")
	let compare = compare
	let pp_print_sep fmt () = Format.pp_print_string fmt ", "
end
module StringList = OUnitDiff.ListSimpleMake(StringDiff)

module IntDiff = struct
	type t = int
	let pp_printer fmt i = Format.pp_print_string fmt (string_of_int i)
	let compare = compare
	let pp_print_sep fmt () = Format.pp_print_string fmt ", "
end
module IntList = OUnitDiff.ListSimpleMake(IntDiff)

let string_of_highlight = function
	| Highlighted s -> "[" ^ s ^ "]"
	| Plain "" -> "()"
	| Plain s -> s

module HighlightDiff = struct
	type t = Search.Highlight.fragment
	let pp_printer fmt diff =
			Format.pp_print_string fmt (string_of_highlight diff)
	let compare a b =
		Printf.eprintf "Compare %s -> %s = %d\n" (string_of_highlight a) (string_of_highlight b) (
			match a, b with
			| Highlighted a, Highlighted b -> compare a b
			| Plain a, Plain b -> compare a b
			| Highlighted _, Plain _ -> -1
			| Plain _, Highlighted _ -> 1
		);
		match a, b with
		| Highlighted a, Highlighted b -> compare a b
		| Plain a, Plain b -> compare a b
		| Highlighted _, Plain _ -> -1
		| Plain _, Highlighted _ -> 1

	let pp_print_sep fmt () = Format.pp_print_string fmt " "
end
module HighlightList = OUnitDiff.ListSimpleMake(HighlightDiff)

let build_entry text =
	let open Search in
	{
		text = text;
		match_text = String.lowercase text;
		input_index = 0;
	}

let score query text =
	let rv = Search.score query (build_entry text) in
	begin match rv with
		| Some (score, matches) ->
			Printf.eprintf "got score = %0.3f, matches = [%s]\n" score (String.concat "," (List.map string_of_int matches))
		| _ -> ()
	end;
	rv


let assert_highlight query input expected =
	match score query input with
		| Some (_score, matches) ->
			HighlightList.assert_equal expected (Search.highlight input matches)
		| None ->
			assert_failure ("No highlight for query " ^ query ^ " on " ^ input)

let assert_match query input expected =
	match expected, score query input with
		| None, None -> ()
		| Some expected, Some (_score, matches) ->
			IntList.assert_equal expected matches

		| Some _, None ->
			assert_failure ("No highlight for query " ^ query ^ " on " ^ input)

		| None, Some (_score, matches) ->
			assert_failure (
				"Unexpected highlight for query " ^ query ^ " on " ^ input ^ ": " ^
				(String.concat "," (List.map string_of_int matches))
			)

let assert_better ~query a b =
	match (score query a), (score query b) with
		| Some (ascore, _), Some (bscore, _) ->
				if ascore = bscore then
					assert_failure "scores equal"
				else if ascore < bscore then
					assert_failure "worse"
		| _ -> assert_failure "query did not match"

let assert_equivalent ~query a b =
	match (score query a), (score query b) with
		| Some (ascore, _), Some (bscore, _) ->
				if ascore <> bscore then
					assert_failure "scores differ"
		| _ -> assert_failure "query did not match"

let () =
	Log.enable_debug := true;
	run_test_tt_main (OUnit2.test_list [
		"match" >::: [
			"must be in order" >:: (fun _ ->
				assert_match "32" "123" None
			);

			"runs of the same character" >:: (fun _ ->
				assert_match "cc" "abcd" None;
			);

			"entire string" >:: (fun _ ->
				assert_match "123" "123" (Some [0;1;2]);
			);
		];

		"highlighting" >::: [
			"single characters" >:: (fun _ ->
				assert_highlight "16" "123456" [Highlighted "1"; Plain "2345"; Highlighted "6"];
				assert_highlight "3" "12345" [Plain "12"; Highlighted "3" ; Plain "45"];
				assert_highlight "2" "123" [Plain "1"; Highlighted "2"; Plain "3"];
			);

			"multiple characters" >:: (fun _ ->
				assert_highlight "123" "123" [Highlighted "123"];
				assert_highlight "23" "12345" [Plain "1"; Highlighted "23" ; Plain "45"];
			);

			"multiple runs" >:: (fun _ ->
				assert_highlight "12356" "123456" [Highlighted "123"; Plain "4"; Highlighted "56"];
			);

			"runs of the same character" >:: (fun _ ->
				assert_highlight "pp" "Happpy" [Plain "Ha"; Highlighted "pp"; Plain "py"];
			);

			"highlights runs over word leaders" >:: (fun _ ->
				assert_highlight "sea" "src/search.ml" [Plain "src/"; Highlighted "sea"; Plain "rch.ml"];
			);
		];

		"scoring" >::: [
			"word boundaries (.)" >:: (fun _ ->
				assert_better ~query:"ml" "foo.ml" "foorml"
			);
			"word boundaries (camelcase)" >:: (fun _ ->
				assert_better ~query:"ml" "fooMl" "fooml"
			);
			"word boundaries (leading)" >:: (fun _ ->
				assert_better ~query:"f" "foo" "oof"
			);
			"uppercase names aren't treated as word boundaries" >:: (fun _ ->
				assert_equivalent ~query:"hvew" "HTTPViewer" "httpviewer"
			);

			"prefers adjacent letters" >:: (fun _ ->
				assert_better ~query:"ab" "abcd" "acbd"
			);

			"prefers word leaders" >:: (fun _ ->
				assert_better ~query:"c" "cd" "dc"
			);

			"a better match stops being preferred if it adds 5 characters per point" >:: (fun _ ->
				assert_better ~query:"c" "cd123" "dc";
				assert_better ~query:"c" "dc" "cd123456";
			);
		];


	])
