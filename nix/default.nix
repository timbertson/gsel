{pkgs}:
{src, version}:
with pkgs;
let oc = ocamlPackages_4_01_0;
in stdenv.mkDerivation {
	name = "gsel-${version}";
	inherit src;
	buildInputs = [
		oc.ocaml
		oc.lablgtk
		oc.findlib
		oc.sexplib
		oc.ounit
		pkgconfig
		gnome.glib
		gnome.gtk
		gup
		(callPackage ./xlib.nix {ocamlPackages = oc;})
	];
	buildPhase = "gup bin/all";
	installPhase = ''
		mkdir $out
		cp -r bin $out/bin
		mkdir $out/share
		cp -r share/{vim,fish} $out/share/
	'';
}
