{pkgs ? import <nixpkgs> {}, ocamlPackages ? pkgs.ocamlPackages_latest}:
with pkgs;
stdenv.mkDerivation {
	name = "ocaml-xlib";
	src = fetchgit {
		url = "https://github.com/gfxmonk/ocaml-xlib.git";
		# url = "/home/tim/dev/ocaml/xlib";
		rev = "fbd61568f100a92722bd7868395b71ac8043f6f5";
		sha256="76f7fed11f6d7d99d5e33844906bf64724493cbc624a18d493a8b6555d698273";
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
