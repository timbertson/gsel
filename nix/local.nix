{pkgs ? import <nixpkgs> {}}:
import ./default.nix
	{ inherit pkgs; }
	{ src = ./local.tgz; version="local"; }
