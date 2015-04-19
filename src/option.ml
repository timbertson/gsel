let may o f = match o with
	| Some o -> f o; ()
	| None -> ()

let map o f = match o with
	| Some o -> Some (f o)
	| None -> None
