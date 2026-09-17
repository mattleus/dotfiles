# 2. Firstmate fleet in-container, working clone + PR

Date: 2026-09-17
Status: accepted

## Context

The sandbox needs to host two kinds of agent work: direct human-driven
pi/opencode sessions on host repos, and firstmate's multirepo fleet. Two shapes
were on the table: the fleet driving host checkouts from outside the boundary,
or the fleet running inside it.

Running the fleet on the host with only crewmates in containers has no working
backend: firstmate is an orchestration distro whose tmux-based execution model
has no host-to-container channel, so "supervisor on host, workers in the box"
isn't a buildable option in v1. Letting the fleet edit host checkouts directly
would put unpushed, host-resident work inside the blast radius with no review
gate between the agent and main.

## Decision

The whole fleet - firstmate, tmux, treehouse, crewmates - runs inside the
sandbox. It clones repos under FM_HOME/projects/ from git remotes; direct
sessions use the bind-mounted ~/work instead, and the two never meet. Fleet
delivery is PR-first (via gh over HTTPS with the session-injected token), or
approved local merges for projects in local-merge mode. The review loop for
fleet work is PR review on the host; host checkouts are never touched by the
fleet. The fleet's FM_HOME tree satisfies firstmate's machine-local lock
requirement by being one filesystem view.

## Consequences

- Fleet force-pushes hit disposable clones; the enforceable protection for
  shared history is server-side (GitHub branch protection), not local.
- Unpushed fleet work lives in one mounted tree; losing it is the accepted
  risk recorded in the recovery matrix (no host backups in v1).
- The human enters the fleet via ssh into the container (tmux persistence);
  `docker exec` remains the root-level escape hatch only.
