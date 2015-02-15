{pkgs ? import <nixpkgs> {}}:
with pkgs;
let oc = ocamlPackages_4_01_0;
in stdenv.mkDerivation {
	name = "gsel";
	buildInputs = [
		oc.ocaml
		oc.lablgtk
		oc.findlib
		oc.ounit
		pkgconfig
		gnome.libwnck
		gnome.glib
		gnome.gtk
		(callPackage ./nix/gup.nix {})
	];
}
