{pkgs ? import <nixpkgs> {}}:
with pkgs;
let oc = ocamlPackages_4_01_0;
in stdenv.mkDerivation {
	name = "gsel";
	buildInputs = [
		oc.ocaml
		oc.findlib
		pkgconfig
		gnome.glib
		gnome.gtk
		oc.ocaml_sexplib
		(callPackage ./nix/gup.nix {})
	];
}
