# scripts

Personal dev-station command-line tools. Each file here is linked onto `PATH`
via `~/.local/bin` by `home.nix` using an out-of-store symlink, so:

- the script is available anywhere once `darwin-rebuild switch` has run on a machine, and
- editing a script in this repo is **instantly live** — no rebuild needed (same
  edit-in-place pattern as the `~/.config/*` links).

## Adding a new script

1. Drop the file in this folder and make it executable: `chmod +x scripts/<name>`.
2. Add one line to `home.nix`, next to the other `home.file.".local/bin/*"` entries:

   ```nix
   home.file.".local/bin/<name>".source =
     config.lib.file.mkOutOfStoreSymlink "${dotfiles}/scripts/<name>";
   ```

3. `darwin-rebuild switch` (or `./rebuild.sh`) to create the symlink on this machine.

## Current scripts

| Script | What it does |
|--------|--------------|
| `openalex` | Query the OpenAlex works API — count, per-license breakdown, random sample, raw URL/curl, and per-work license + open-access lookup by PMID/PMCID/DOI (`openalex license [IDs...] --pmcid|--doi --json`; PMCIDs are first mapped to PMIDs via NCBI's ID Converter since OpenAlex currently indexes no PMCIDs). Zero deps (Node 18+ built-in fetch). `openalex help` for usage. |
| `gh-preview` | Open a GitHub HTML file locally via a git worktree (`file://` or `--serve`). `gh-preview --help` for usage. |
