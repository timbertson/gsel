open Ocamlbuild_plugin
open Command

let pwd = Unix.getcwd()
let destdir = try Some (Unix.getenv "DESTDIR") with Not_found -> None

let () = dispatch begin function
	| After_rules ->
		(* flag ["link"; "library"; "ocaml"; "byte"; "use_libcryptokit"] *)
		(*			(S[A"-dllib"; A"-lcryptokit"; A"-cclib"; A"-lcryptokit"]); *)

	let tags = ["link"; "ocaml"; "native"; "use_gselui"] in
	let cmd = [A"-cclib"; A ("-L."); A"-cclib"; A"-lgselui";] in
	let cmd = match destdir with
		| Some destdir -> cmd @ [A"-cclib"; A("-Wl,-rpath,"^destdir^"/lib")]
		| None -> cmd
	in
	flag tags (S cmd);

	(* flag ["link"; "ocaml"; "native"; "use_gselui"] *)
	(* 	(S[A"-cclib"; A (pwd ^ "/valaui/gselui.vala.o")]); *)

	(* dep tags ["valaui/libgselui.so"]; *)
	| _ -> ()
end
