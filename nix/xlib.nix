{pkgs ? import <nixpkgs> {}, ocamlPackages ? pkgs.ocamlPackages_latest}:
with pkgs;
stdenv.mkDerivation {
	name = "ocaml-xlib";
	src = fetchgit {
		url = "https://github.com/gfxmonk/ocaml-xlib.git";
		# url = "/home/tim/dev/ocaml/xlib";
		rev = "977f67f99c9776c39498f619937af485fbd3e2a2";
		sha256="a51961636b31d366557074d386054111aaa37a0867eafac0644af1b3103c2978";
	};
	buildInputs = [
		ocamlPackages.ocaml
		ocamlPackages.lablgtk
		ocamlPackages.findlib
		pkgconfig
		xlibs.libX11
	];
	# preBuild = "sed -i -e '/^directory =/d' META";
	createFindlibDestdir = true;
	installPhase = "make install PREFIX=$OCAMLFIND_DESTDIR/xlib";
}
