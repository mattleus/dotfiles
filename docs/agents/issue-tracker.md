# Issue tracker: Linear

Issues and specs for this repo live in Linear. Use the **Linear MCP server** (registered as `linear` in the global OpenCode config, `~/.config/opencode/opencode.jsonc`) for all operations. The MCP tools are exposed as `linear_*` (Code Mode: `tools.linear.*`); discover the exact tool surfaces at runtime with the MCP resource/tool listing. Linear's hosted MCP supports OAuth 2.1 with dynamic client registration - authenticate once via `/mcps` in OpenCode.

## Conventions

- **Team**: not pinned. Discover teams with the team-listing tool; if the user named a team, use it, otherwise ask or use the workspace's obvious default before creating anything.
- **Create an issue**: the create-issue tool, with team id, title, body (Markdown), labels (see `triage-labels.md`).
- **Read an issue**: the get-issue tool, including comments, for identifier `ABC-123` style keys.
- **List issues**: the list-issues tool, filtered by label or state.
- **Comment on an issue**: the create-comment tool.
- **Apply / remove labels**: the update-issue tool (or label tools) with the Linear label ids; list labels first to map names to ids, creating missing labels via the create-label tool.
- **Close**: update-issue with the team's completed/cancelled state id (discover state ids via the workflow-states listing).

## When a skill says "publish to the issue tracker"

Create a Linear issue.

## When a skill says "fetch the relevant ticket"

Read the Linear issue for the given identifier (e.g. `ABC-123`) including its comments.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with tickets as children.

- **Map**: one issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body.
- **Child ticket**: an issue linked to the map as a Linear sub-issue (use the sub-issue/parent field on create or update if the MCP exposes it; otherwise put `Part of <map-id>` at the top of the child body and a task list in the map body). Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, assign the ticket to the driving dev (look up the user id via the user-listing tool).
- **Blocking**: Linear's **native blocking relation**, the canonical, UI-visible representation. Use the relation tool if the MCP exposes one (relation type `blocks`/`blocked by`); otherwise fall back to a `Blocked by: <id>, <id>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children, drop any with an open blocker or an assignee; first in map order wins.
- **Claim**: assign the issue to yourself (the authenticated Linear user), the session's first write.
- **Resolve**: comment the answer on the issue, close it, then append a context pointer to the map's Decisions-so-far.
