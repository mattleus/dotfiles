# 5. Per-owner GitHub token dispatch instead of one session token

Date: 2026-09-22
Status: accepted

## Context

ADR 0002's "PR-first (via gh over HTTPS with the session-injected token)"
assumed one GH_TOKEN can serve a session. The estate spans three github.com
owners - cohere-ai, Reliant-AI, and mattleus/* - each reachable only by its
own host `gh` account (verified over the API: no account can read both orgs'
repos), and a fine-grained PAT has a single resource owner, so the documented
`sandbox-gh-token` fix could only ever move 404s from one org to the other.
Sessions with no repo context (`workbench ssh`/`herdr`, the fleet entries)
fell back to the host's *active* gh account, so the fleet silently 404'd
whichever org that account was not in - reproduced as Reliant-AI being
inaccessible from firstmate sessions.

## Decision

Inject all three host account tokens per session as
`GH_TOKEN_{COHERE,RELIANT,PERSONAL}` (ambient `GH_TOKEN` = the personal
account) and dispatch per repo owner **inside** the sandbox:

- gh calls: `/usr/local/bin/gh`, a shim shadowing the real binary via PATH
  order (firstmate and gh-axi both exec plain `gh`, so it intercepts them
  too), picks the token from `-R`/`--repo` args, `api repos/<owner>/...`
  endpoints, `repo view|clone|fork` positionals, or the cwd's origin remote -
  including the host's `git@github-{reliant,cohere,personal}:` ssh aliases.
  Unresolvable calls (e.g. `gh api graphql`) keep the ambient token.
- git transports: `credential.useHttpPath=true` so every credential query
  carries the repo path, and the baked `workbench-gh-cred` helper answers with
  the token for the path's owner (ambient GH_TOKEN for unknown owners).

A `sandbox-gh-token` keychain PAT, when present, remains a single-token escape
hatch (only GH_TOKEN injected; the dispatch naturally degrades to it). The
owner-to-account mapping lives in exactly three places, cross-referenced by
comments and pinned by tests/workbench.test.sh behavior cases: the wrapper's
`acct_*` vars, the two `docker/workbench/bin/` scripts, and home.nix's gh
autoswitch.

## Consequences

- Fleet sessions and direct sessions alike authenticate every GitHub operation
  as the owning account; central loops iterating projects across owners
  (bearings snapshots, PR sweeps) work from one process.
- Rotating a host gh login takes effect on the next session; the sandbox holds
  no GitHub state to rotate.
- Nothing human left to provision for GitHub: the PAT is optional, not the
  primary path.
