#!/usr/bin/env bash
set -eux
GUP="$(nix-build --no-out-link -A gup '<nixpkgs>')/bin/gup"
"$GUP" nix/local.tgz

# first, run a nix-shell to check dependencies
# (verbose; so we only log it if it fails)

env NTH_LINE=500 SUMMARIZE=stderr python <(curl -sSL 'https://gist.githubusercontent.com/timbertson/0fe86d8208146232bf0931a525cd9a9f/raw/long-output.py') \
	nix-shell --show-trace --run true

# dependencies OK; run a build
nix-build --show-trace
echo "== Built files:"
ls -lR result/
