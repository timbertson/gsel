{pkgs ? import <nixpkgs> {}, shell ? false}:
import ./default.nix
	{ inherit pkgs shell; }
	{ src = ./local.tgz; version="local"; }
