{pkgs, shell ? false}:
{src, version}:
with pkgs;
let
	opam2nix = callPackage ./opam2nix-packages.nix {};
	opamDeps = [
		"ocamlfind" "sexplib" "ppx_sexp_conv" "ounit"
		"conf-pkg-config" "ctypes" "ctypes-foreign"
	]
	;
	opamConfig = {
		packages = opamDeps;
		ocamlAttr = "ocaml_4_03";
		args= ["--verbose" ];
	};
	opamPackages = opam2nix.buildPackageSet opamConfig;

in stdenv.mkDerivation {
	name = "gsel-${version}";
	inherit src;
	buildInputs = opam2nix.build opamConfig ++ [
		pkgconfig
		gup
		gnome3.vala
		gnome3.gtk
		(callPackage ./xlib.nix {ocamlPackages = opam2nix.buildPackageSet opamConfig;})
	] ++ (if shell then [
		python
	] else []);
	passthru = {
		inherit opamPackages;
	};
	buildPhase = "env PREFIX=$out gup bin/all";
	installPhase = ''
		cp -r _build/lib/*.so $out/lib
		cp -r --dereference bin $out/bin
		mkdir -p $out/share
		cp -r share/{vim,fish} $out/share/
	'';
	shellHook = ''
		export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${opamPackages.ctypes}/lib/ctypes"
	'';
}
