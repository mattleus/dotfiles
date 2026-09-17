# 3. Wholesale ~/work mount after secrets relocation

Date: 2026-09-17
Status: accepted

## Context

Direct sessions need bind-mounted host repos, and firstmate sessions span many
repos; "one repo at a time" mounting was vetoed at charting because the
multirepo workflow can't name its repo set in advance. The open question was
the exposure of sensitive files inside that whole tree.

~/work contained loose secret outliers: an env dump and a
key-listing script in reliant-ai, a .env.backup in cohere-ai. Mounting the
tree wholesale would have put those inside the blast radius - not exfiltration
(malicious code is out of the v1 threat model) but sloppy secret hygiene the
threat model's secondary axis does care about.

## Decision

Mount ~/work wholesale, but first relocate the sensitive outliers into
~/.secrets/work/ (a host directory the sandbox never mounts), verified by
audit: three files moved, zero repo references to the old paths left behind.
The ~/work symlinks into ~/repos/github/{cohere-ai,reliant-ai} are followed by
mounting those targets at identical absolute paths. Gitignored .env files that
apps legitimately need stay in the tree (opencode's baked .env read-deny covers
the cheap hygiene); the gitignored/normal case is explicitly out of the cleanup
scope. Simplicity over selective mounts: one rule ("~/work goes in; secrets
don't live there") beats a maintained allowlist.

## Consequences

- Relocated secrets are unreachable from the sandbox by topology, not by rule.
- Residual exposure survives in tracked-in-git history (north's env files,
  infra's Cloudflare token manifest) because clones from remotes carry them;
  rotation is a human call outside this effort and is recorded as residual.
- New loose secrets dropped into ~/work would ride the next mount - the
  relocated-secrets home is convention guarded by audit, not mechanism.
