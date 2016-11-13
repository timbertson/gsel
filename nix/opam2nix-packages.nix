
{ pkgs ? import <nixpkgs> {}}:
with pkgs;
let
	# For development, set OPAM2NIX_DEVEL to your local
	# opam2nix repo path
	devRepo = builtins.getEnv "OPAM2NIX_DEVEL";
	src = fetchgit {
  "url" = "https://github.com/timbertson/opam2nix-packages.git";
  "fetchSubmodules" = false;
  "sha256" = "1zja9miiacsscqwqvw2b350h4b8n5k6rlc90qh6gsh37mx8kbjvx";
  "rev" = "f62e640a046271cd8b9ef8f0713ccfe35f5c4da1";
};
	opam2nix = fetchgit {
  "url" = "https://github.com/timbertson/opam2nix.git";
  "fetchSubmodules" = false;
  "sha256" = "07k1swzk2ny47l8ix9fg2lhfaks9fz2jfj3m7n811k4vcgp0glpn";
  "rev" = "580f5808f22535dc618a60641d8cef5674b6fe36";
};
in
if devRepo != "" then
	let toPath = s: /. + s; in
	callPackage "${devRepo}/nix" {} {
			src = toPath "${devRepo}/nix/local.tgz";
			opam2nix = toPath "${devRepo}/opam2nix/nix/local.tgz";
		}
else callPackage "${src}/nix" {} { inherit src opam2nix; }
