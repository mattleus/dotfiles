# 1. Agent-in-container over host sandboxing

Date: 2026-09-17
Status: accepted

## Context

Coding agents (pi, opencode) need full-power local execution while their
mistakes (rm -rf, out-of-repo writes, force-pushes) must not damage this Mac
beyond recovery. Two placements were considered: agent-on-host with per-command
OS sandboxing, or the whole agent process inside a disposable container.

Per-command OS sandboxing does not exist for either tool: pi ships no built-in
sandbox by design (its own security docs direct users to OS/container
boundaries), and opencode's permissions are string patterns evaluated
pre-tool-call - enforceable against the model but trivially routed around via
shell indirection. macOS Seatbelt could in theory bound a bespoke profile, but
it is deprecated for new bespoke profiles. There is, in short, no per-command
boundary to build on the host.

## Decision

The whole agent process runs inside one disposable "workbench" container on
the existing Colima stack (vz + virtiofs). Every child process, MCP server, and
extension inherits the boundary. The container runs as non-root uid 501 with
HOME=/Users/matt (identical path spelling in and out), never mounts
docker.sock, and mounts only the paths the sandbox needs. The container is the
only load-bearing boundary; everything layered on top (opencode permission
rules, the pre-push tripwire, conventions) is honestly labeled a speed bump.
`docker rm` resets all container-layer state.

## Consequences

- Blast radius of an agent mistake = container filesystem + the explicitly
  bind-mounted host paths; everything else is unreachable by construction.
- Container-side file watchers cross a virtiofs mount (small-file churn
  ~2.4-2.6x slower; caches therefore live in named volumes), and mounts are
  case-insensitive (APFS). Both are accepted.
- The VM shares the 8 vCPU / 20 GiB shape with other work (dataharness);
  resizing pauses them and was scheduled around it.
