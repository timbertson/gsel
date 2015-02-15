open Ocamlbuild_plugin
open Command

let () =
  let make_opt o arg = S [ A o; arg ] in
	let pkg_config flags package =
		let has_package =
			try ignore (run_and_read ("pkg-config --exists " ^ package)); true
			with Failure _ -> false
		in
		let cmd tmp =
			Command.execute ~quiet:true &
			Cmd( S [ A "pkg-config"; A ("--" ^ flags); A package; Sh ">"; A tmp]);
			List.map (fun arg -> A arg) (string_list_of_file tmp)
		in
		if has_package then with_temp_file "pkgconfig" "pkg-config" cmd else (Printf.printf "Note: %s not found...\n" package; [])
	in

	dispatch ( function
		| After_rules ->
				dep ["link"; "ocaml"; "use_wnck"] ["src/wnck.o"];
				let wnck = "libwnck-1.0" in
				flag ["compile"; "use_wnck"] (S(List.map (make_opt "-ccopt") (pkg_config "cflags" wnck)));
				flag ["link"; "use_wnck"] (S(List.map (make_opt "-cclib") (pkg_config "libs" wnck)));
		| _ -> ()
	)
