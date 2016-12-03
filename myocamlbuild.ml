open Ocamlbuild_plugin
open Command

let pwd = Unix.getcwd()
let destdir = try Some (Unix.getenv "PREFIX") with Not_found -> None

let () = dispatch begin function
	| After_rules ->
	let tags = ["link"; "ocaml"; "native"; "use_gselui"] in
	let cmd = [A"-cclib"; A"-L./lib"; A"-cclib"; A"-lgselui"; A"-cclib"; A"-Wl,--export-dynamic"] in
	let cmd = match destdir with
		| Some destdir -> cmd @ [A"-cclib"; A("-Wl,-rpath,"^destdir^"/lib")]
		| None ->
			prerr_endline "Not using rpath, set $PREFIX to enable";
			cmd
	in
	flag tags (S cmd);
	| _ -> ()
end
