# 4. FM_HOME as a host bind mount, not a volume

Date: 2026-09-17
Status: accepted

## Context

The fleet's home (config, state, data, and the projects/ clones) has to live
somewhere durable. The image research recommended a named volume: ext4 in-VM,
~12x faster on small-file churn than the virtiofs bind mount, and the natural
reading of "everything durable is a volume."

The recovery-story grilling modified that: the fleet home should stay visible
and browsable on the host exactly as it is today via ~/firstmate - supervisor
status files, per-repo clones, and treehouse worktrees all readable with host
tools without entering the container. Host visibility won over ext4 speed.

## Decision

FM_HOME is the existing host fleet home at ~/repos/public/firstmate, bind-
mounted read-write at the identical absolute path (with the image symlinking
~/firstmate to it, as on the host). One mount = one filesystem view, which
firstmate's machine-local lock requirement needs. Named volumes remain only
for disposable things where host visibility is worthless: npm cache, mise
toolchains, pi/opencode session data.

## Consequences

- Fleet small-file churn (clones, worktree spawns, npm installs inside clones)
  rides virtiofs at ~2.4x slower sequential writes; accepted for v1, with the
  per-clone volume overlay as the documented escape hatch if it ever hurts.
- FM_HOME damage (state/data) recovers by re-clone + rebuild of firstmate's
  regenerable state; no v1 backups of that tree either.
- Projects cloned under FM_HOME/projects/ on the host before the sandbox
  existed are visible to the fleet in-container unchanged - same paths, same
  git checkouts, same remotes (rewritten to HTTPS by the baked insteadOf
  rules when pushes happen).
