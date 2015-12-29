{pkgs ? import <nixpkgs> {}, ocamlPackages ? pkgs.ocamlPackages_latest}:
with pkgs;
let
	dev_repo = builtins.getEnv "OCAML_XLIB_DEVEL";
	toPath = s: /. + s;
in
if dev_repo != ""
then callPackage (toPath "${dev_repo}/nix/local.nix") {}
else stdenv.mkDerivation {
	name = "ocaml-xlib";
	src = fetchgit {
		url = "https://github.com/fccm/ocaml-xlib.git";
		rev = "069311d1abbd9ee7420cc2fb29781531ccf65529";
		sha256="e0ec165ae9f73b4b77044cf4f3f3d6a9cb1ca17e91cda5d3cfa6ce5a9bbda402";
	};
	buildInputs = [
		ocamlPackages.ocaml
		# ocamlPackages.lablgtk
		ocamlPackages.findlib
		pkgconfig
		xlibs.libX11
	];
	preBuild = "cd src";
	createFindlibDestdir = true;
	installPhase = "make install PREFIX=$OCAMLFIND_DESTDIR/xlib";
}

