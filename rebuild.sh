#!/usr/bin/env bash
set -euo pipefail
# Resolve the symlink chain (e.g. ~/.local/bin/rebuild -> ~/.dotfiles/rebuild.sh
# -> <repo>/rebuild.sh) back to the real repo file before deriving DIR; otherwise
# DIR ends up in .local/bin and ~/.dotfiles gets pointed at .nix-less territory.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do SOURCE="$(readlink "$SOURCE")"; done
DIR="$(cd "$(dirname "$SOURCE")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
exec sudo darwin-rebuild switch --flake ~/.dotfiles#mac
