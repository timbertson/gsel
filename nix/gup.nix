{pkgs ? import <nixpkgs> {}}:
with pkgs;
let version="0.4.0";
in stdenv.mkDerivation {
	name = "gup-${version}";
	buildInputs = [
		python
	];
	src = fetchurl {
		url = "http://gfxmonk.net/dist/0install/impl/gup/gup-${version}.tar.gz";
		sha256="087cahky87q5l0s64kpl2y9k8r58i8vjp6n3jlwrf7gvl8pk0q21";
	};
	unpackPhase = "mkdir src; cd src; tar xf $src";
	buildPhase = "true";
	installPhase = ''
		cp -r python/bin $out/
	'';
}
