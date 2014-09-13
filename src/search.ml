open Log

type entry = {
	text : string;
	match_text : string;
	input_index : int;
}

type search_result = {
	result_source : entry;
	result_parts : string list;
}


let matches needle haystack =
	(* debug ("Looking for "^ needle ^" in "^haystack); *)
	let nl = String.length needle in
	let hl = String.length haystack in
	let rec loop (nh, ni) (hh, hi) =
		if nh = hh then (
				(* move on to next search character *)
				let ni = succ ni
				and hi = succ hi in
				if (ni = nl) then true else
					if (hi = hl) then false else
						loop (String.get needle ni, ni) (String.get haystack hi, hi)
		) else (
				(* move on to next potential character *)
				let hi = succ hi in
				if (hi = hl) then false else
					loop (nh, ni) (String.get haystack hi, hi)
		)
	in
	if nl = 0 then true else
		if hl = 0 then false else
			loop (String.get needle 0, 0) (String.get haystack 0, 0)


let highlight query item =
	(* returns a list of [OFF;ON; OFF; <...>], the first and last of which are always OFF *)
	(* TODO: condense adjacent matching chars into ["abc"] instad of ["a";"";"b";"";"c"] *)
	let match_text = item.match_text in
	let display_text = item.text in
	let text_i = ref 0 in
	let rv = ref [] in (* Note: built in reverse *)
	String.iter (fun ch ->
		let last_pos = !text_i in
		let search_pos = max (last_pos-1) 0 in
		let match_pos = String.index_from match_text search_pos ch in
		text_i := match_pos+1;
		(* let off_start = last_pos+1 in *)
		let diff = match_pos - last_pos in
		let diff = if diff < 0 then 0 else diff in (* XXX *)
		(* debug "OFF: subbing %d*%d of %s" last_pos diff display_text; *)
		rv := (String.sub display_text last_pos diff) :: !rv;

		(* debug "ON %c: subbing %d*%d of %s" ch (match_pos) 1 display_text; *)
		rv := (String.sub display_text (match_pos) 1) :: !rv;
	) query;

	let remaining = String.length match_text - (!text_i) in
	(* debug "REM: subbing %d*%d of %s" (!text_i) remaining display_text; *)
	rv := (String.sub display_text (!text_i) remaining) :: !rv;
	{result_source = item; result_parts= List.rev !rv;}
;;
