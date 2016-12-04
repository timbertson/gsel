let may f = function
	| Some o -> f o; ()
	| None -> ()

let map f = function
	| Some o -> Some (f o)
	| None -> None

let default d = function
	| Some o -> o
	| None -> d

let bind f = function
	| Some o -> f o
	| None -> None
