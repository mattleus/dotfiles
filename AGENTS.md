# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- `homebrew.onActivation.cleanup = "zap"` in `configuration.nix` is intentional. It forces the good habit of declaring every Homebrew package in the Nix config instead of installing things ad-hoc, which keeps the machine reproducible. Do not soften it to `uninstall` or `none`. Users are warned about its effect in README.md; this note is for anyone tempted to change the setting itself.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.
- Tools with no Homebrew formula and no nixpkgs package are declared via `home.activation` blocks at the end of `home.nix` (see `installNoMistakes`, `cloneFirstmate`, `installAxiTools`, `installMattPocockSkills`), each guarded by a `command -v`/path check so re-running `darwin-rebuild switch` is a no-op. Follow this pattern for future tools in the same situation rather than installing them by hand.
- opencode is the deliberate exception: it HAS a nixpkgs package and a Homebrew formula, but it is NOT declared in `home.packages`. `home.activation.installOpenCode` installs it to `~/.opencode/bin` via the official installer (`--no-modify-path`), because opencode updates itself from inside the app and a read-only Nix store binary can't be replaced. Do not move it back into `home.packages`; keep the `~/.opencode/bin` entry in `home.sessionPath`.
- OpenSuperWhisper launches at login via the `launchd.user.agents.opensuperwhisper` user LaunchAgent in `configuration.nix` (not the app's own login-item toggle, which would be non-declarative and double-launch it).
- Agent skills (mattpocock pack + any future `skills add -g`) land canonically in `~/.agents/skills/` with per-agent symlinks. `~/.config/opencode` symlinks into this repo, so anything installed under it (e.g. `skills/`) must stay gitignored - vendored blobs must never be committed.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
