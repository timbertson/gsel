{pkgs, shell ? false}:
{src, version}:
with pkgs;
let
	opam2nix = callPackage ./opam2nix-packages.nix {};
	opamDeps = ["lablgtk" "ocamlfind" "sexplib" "ppx_sexp_conv" "ounit" "conf-pkg-config"];
	opamConfig = {
		packages = opamDeps;
		ocamlAttr = "ocaml_4_03";
		args= ["--verbose" ];
	};

in stdenv.mkDerivation {
	name = "gsel-${version}";
	inherit src;
	buildInputs = opam2nix.build opamConfig ++ [
		pkgconfig
		gnome2.glib
		gnome2.gtk
		gup
		(callPackage ./xlib.nix {ocamlPackages = opam2nix.buildPackageSet opamConfig;})
	] ++ (if shell then [
	gnome2.gtk gnome2.gtksourceview
	# gnome3.gtk gnome3.gtksourceview
	python
	] else []);
	passthru = {
		opamPackages = opam2nix.buildPackageSet opamConfig;
	};
	buildPhase = "gup bin/all";
	installPhase = ''
		mkdir -p $out
		cp -r bin $out/bin
		mkdir -p $out/share
		cp -r share/{vim,fish} $out/share/
	'';
}
