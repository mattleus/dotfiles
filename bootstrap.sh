#!/usr/bin/env bash
# Takes a fresh Mac from nothing to a built nix-darwin config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "==> Step 1: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: personalize the configured username"
# Do this before any sudo call: sudo resets $USER to root, so whoami has to
# run as the real interactive user first.
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 4: first darwin-rebuild switch (pinned to nix-darwin-26.05)"
# darwin-rebuild doesn't exist yet on a fresh machine, so run it straight
# from the flake this once. After this, rebuild.sh works normally.
# This fetches the darwin-rebuild tool from the nix-darwin-26.05 release branch,
# not the exact flake.lock revision. The system config it applies is still pinned
# by this repo's flake.lock.
# sudo resets PATH to a secure default that excludes /nix/.../bin, so a
# freshly installed `nix` would not be found under sudo even though it's
# on PATH here. Resolve the absolute path first and invoke that instead.
NIX_BIN="$(command -v nix)"
# "mac" is the flake host label - if you renamed it, change it in flake.nix
# and rebuild.sh too.
sudo "$NIX_BIN" run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake ~/.dotfiles#mac
# If this still fails with "nix: command not found", open a new terminal
# (Determinate adds nix to new shells' PATH) and re-run ./bootstrap.sh.

echo "==> Step 5: colima VM sizing (workbench expects 8 vCPU / 20 GiB / 100 GiB)"
# colima only applies --cpu/--memory/--disk when CREATING the VM; sizing an
# existing VM means colima stop + start with the flags (which pauses other
# containers on it). On a fresh machine the VM doesn't exist yet, so create it
# at the right shape directly; the zsh hook would otherwise auto-start it with
# defaults on the first new shell.
if ! colima status >/dev/null 2>&1; then
  colima start --cpu 8 --memory 20 --disk 100 --vm-type vz --mount-type virtiofs --mount-inotify
else
  shape="$(colima list | awk '$1=="default" {print $4, $5}')"
  if [ "$shape" != "8 20GiB" ]; then
    echo "    colima VM is running at a different shape ($shape). When convenient"
    echo "    (it pauses any other containers on the VM):"
    echo "      colima stop && colima start --cpu 8 --memory 20 --disk 100 --vm-type vz --mount-type virtiofs --mount-inotify"
  fi
fi
# Machine-local items bootstrap deliberately does NOT set up (check-and-prompt
# instead): the COHERE_API_KEY and sandbox-gh-token keychain entries (the
# workbench wrapper prompts/reads them), the fine-grained PAT on GitHub,
# branch protection on org repos without admin, firstmate per-clone trust.
echo "    Reminder: the workbench's first session prompts for COHERE_API_KEY"
echo "    (paste from Bitwarden; stored as a keychain generic password). If you"
echo "    also want the dedicated fine-grained PAT for git/gh in the sandbox:"
echo "    security add-generic-password -s sandbox-gh-token -a \"\$USER\" -w \"<pat>\""

echo "==> Done. Use ./rebuild.sh for future changes."
