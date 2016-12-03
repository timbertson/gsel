(* TODO: reshuffle order *)
let may o f = match o with
	| Some o -> f o; ()
	| None -> ()

let map o f = match o with
	| Some o -> Some (f o)
	| None -> None

let default o d = match o with
	| Some o -> o
	| None -> d

let bind f o = match o with
	| Some o -> f o
	| None -> None
