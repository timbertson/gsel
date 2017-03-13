#!/usr/bin/env bash
set -eux
bash <(curl -sS https://gist.githubusercontent.com/timbertson/f643b8ae3a175ba8da7f/raw/travis-nix-bootstrap.sh)
source $HOME/.nix-profile/etc/profile.d/nix.sh

GUP="$(nix-build --no-out-link -A gup '<nixpkgs>')/bin/gup"
$GUP nix/local.tgz

# first, run a nix-shell to check dependencies
# (verbose; so we only log it if it fails)
tools/failtail -n 500 --lines 100 -- nix-shell --show-trace --run true

# dependencies OK; run a build
nix-build --show-trace
echo "== Built files:"
ls -lR result/
