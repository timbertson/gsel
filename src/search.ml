open Log

type entry = {
	text : string;
	match_text : string;
	input_index : int;
}

type search_result = {
	result_source : entry;
	result_score : int;
	match_indexes : int list;
}

type intermediate_score = (int * int list) option
let better_score (a: intermediate_score) (b:intermediate_score) : intermediate_score =
	match a, b with
		| None, None -> None
		| Some _, None -> a
		| None, Some _ -> b
		| Some (ascore, _), Some (bscore, _) ->
			debug "Comparing score %d <=> %d" ascore bscore;
			if ascore >= bscore then a else b

let explode : string -> char list = fun s ->
	let rec exp i l =
		if i < 0 then l else exp (i - 1) (s.[i] :: l) in
	exp (String.length s - 1) []

let is_lowercase_alpha c = (c >= 'a' && c <= 'z')
let is_uppercase_alpha c = (c >= 'A' && c <= 'Z')
let is_digit c = (c >= '0' && c <= '9')
let is_alphanum c = (is_lowercase_alpha c || is_uppercase_alpha c || is_digit c)

(* constants *)
let run_score = 3
let word_leader_score = 2
let match_score = 1

let score query item =
	let query = explode query in
	let match_text = item.match_text in
	let display_text = item.text in
	let last_idx = String.length item.match_text - 1 in
	debug "Score: '%s' (last_idx=%d)" item.text last_idx;

	let rec score_at idx in_run ch remaining_query : intermediate_score =
		debug "query '%c' at index %d" ch idx;
		if idx > last_idx then
			None
		else begin
			let first_match =
				try Some (String.index_from match_text idx ch)
				with Not_found -> None
			in
			match first_match with
				| None ->
						debug "None";
						None
				| Some first_match -> begin
					debug "first match: %d" first_match;
					let remaining_score =
						match remaining_query with
							| [] -> Some (0, [])
							| q::uery ->
									debug "recursing on '%c' from %d" q first_match;
									score_at (first_match+1) true q uery
					in
					match remaining_score with
						| None -> None
						| Some (remaining_score, remaining_highlighted) ->
							let this_highlighted = (first_match::remaining_highlighted) in
							if first_match = idx && in_run then (
								(* this is the best match we're going to get *)
								debug "found best match: '%c' @%d" ch idx;
								Some ((run_score + remaining_score), this_highlighted)
							) else (
								(* return whatever's better between taking & skipping this match *)
								(* debug "previous letter: %c" (if first_match = 0 then '?' else display_text.[first_match-1]); *)
								let is_leader =
									if first_match = 0 then true else (
										let preceeding_letter = display_text.[first_match-1] in
										let this_letter = display_text.[first_match] in
										(is_uppercase_alpha this_letter && not (is_uppercase_alpha preceeding_letter)) ||
										(is_lowercase_alpha this_letter && not (is_alphanum preceeding_letter))
									)
								in
								let this_score = if is_leader then word_leader_score else match_score in
								debug "match @ %d is worth %d, trying from %d" first_match this_score (first_match+1);
								better_score
									(Some (this_score + remaining_score, this_highlighted))   (* accept this match *)
									(score_at (first_match+1) false ch remaining_query) (* skip this match *)
							)
				end
		end
	in
	if match_text = "" then None else match query with
		| [] -> Some (0, [])
		| q::uery -> score_at 0 false q uery


module Highlight = struct
	type fragment =
		| Highlighted of string
		| Plain of string
end

let highlight str indexes : Highlight.fragment list =
	let open Highlight in
	let rec continue_match section_start idx indexes =
		debug "continue_match[%d-%d]" section_start idx;
		match indexes with
			| [] ->
				(* end the "on" section *)
				debug "REM on_part: %d * %d" section_start (idx+1 - section_start);
				let on_part = String.sub str section_start (idx+1 - section_start) in
				(Highlighted on_part) :: (continue_nomatch (idx+1) indexes)

			| next_match :: next_indexes ->
				if next_match = idx+1 then (
					debug "Extending match from %d -> %d" idx (idx+1);
					continue_match section_start (idx+1) next_indexes
				) else (
					debug "on_part: %d * %d" section_start (idx+1 - section_start);
					let on_part = String.sub str section_start (idx+1 - section_start) in
					(Highlighted on_part) :: (continue_nomatch (idx+1) indexes)
				)

	and continue_nomatch idx indexes =
		debug "continue_nomatch[%d]" idx;
		match indexes with
			| [] ->
				debug "REM off part: %d * %d" (idx) ((String.length str) - idx);
				let off_part = String.sub str (idx) ((String.length str) - idx) in
				if off_part = "" then [] else [Plain off_part]

			| next_match :: indexes ->
				debug "off_part: %d * %d" idx (next_match - idx);
				let off_part = String.sub str idx  (next_match - idx) in
				let rest = (continue_match next_match next_match indexes) in
				if off_part = "" then rest else (Plain off_part) :: rest
	in

	continue_nomatch 0 indexes
;;
