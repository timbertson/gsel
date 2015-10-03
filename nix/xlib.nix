{pkgs ? import <nixpkgs> {}, ocamlPackages ? pkgs.ocamlPackages_latest}:
with pkgs;
stdenv.mkDerivation {
	name = "ocaml-xlib";
	src = fetchgit {
		url = "https://github.com/gfxmonk/ocaml-xlib.git";
		# url = "/home/tim/dev/ocaml/xlib";
		rev = "83de5bfb9ad23c9f726f3d27a213df7362d5ac11";
		sha256="822d01c74bf08f8fbd610eac73d52f812259cc560b0e58aac95285bf0469db4c";
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
