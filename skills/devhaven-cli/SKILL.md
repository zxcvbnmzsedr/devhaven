---
name: devhaven-cli
description: Control the DevHaven macOS app through the `devhaven` CLI. Use when an agent needs to inspect DevHaven capabilities, query active workspaces, open or activate a workspace, exit the workspace view, close the current session or project, or show, hide, or toggle the Project, Commit, or Git tool windows. Prefer this skill for self-bootstrap flows such as finishing a task and closing the current DevHaven workspace from inside the embedded terminal.
---

# DevHaven CLI

Use the `devhaven` command as the only supported control surface for DevHaven automation.

Do not:

- click the GUI through AppleScript or accessibility automation
- read or write `~/.devhaven/cli-control` directly
- depend on unversioned internal files as the primary control path

## Quick Start

1. Verify the CLI exists.
   Run `command -v devhaven`.
2. Probe capability before doing any mutation.
   Run `devhaven capabilities --json` when available, otherwise run `devhaven status --json`.
3. Prefer current-context targeting for actions initiated from the embedded terminal.
   Use `--current` first.
4. Prefer machine-readable output.
   Add `--json` unless the user explicitly wants plain text.
5. Re-read state after mutations that matter.
   For example, after closing a workspace, run `devhaven status --json` or `devhaven workspace list --json`.

## Phase 1 Workflow

Follow this order:

1. Discover what the local DevHaven build supports.
2. Query current state.
3. Run the smallest mutation that satisfies the request.
4. Verify the new state.
5. If the command is unsupported, say so clearly and stop instead of guessing hidden internals.

## Command Patterns

Read [references/phase1-commands.md](references/phase1-commands.md) for the Phase 1 command matrix.

The most important commands are:

- `devhaven capabilities --json`
- `devhaven status --json`
- `devhaven workspace list --json`
- `devhaven workspace enter --path <path> --json`
- `devhaven workspace activate --path <path> --json`
- `devhaven workspace exit --json`
- `devhaven workspace close --current --scope session --json`
- `devhaven workspace close --current --scope project --json`
- `devhaven tool-window show --kind git --json`
- `devhaven tool-window hide --kind commit --json`
- `devhaven tool-window toggle --kind project --json`

## Targeting Rules

Use this priority order when the user asks about "current" DevHaven context:

1. Explicit `--path` or stable ID from a prior CLI response
2. `--current`
3. Fresh state lookup from `devhaven workspace list --json`

If `--current` fails because context is ambiguous or missing:

1. Run `devhaven workspace list --json`
2. Choose the correct target explicitly
3. Re-run the command with `--path` or returned ID

## Error Handling

Handle failures explicitly:

- If `devhaven` is missing:
  explain that this DevHaven build does not ship the CLI yet, and do not fall back to private IPC or GUI clicking.
- If `capabilities` is missing:
  fall back to `devhaven status --json` and treat the build as an older CLI.
- If a command returns `unsupported_command`:
  stop using that namespace and tell the user the capability is not implemented in this build.
- If a command returns `target_not_found`:
  refresh state with `devhaven workspace list --json` and retry only with an explicit target.
- If the app is not running:
  surface the error clearly. Only attempt launch if the user asked for it or if the CLI explicitly supports a launch flag.

## Response Style

When you use this skill:

- mention the exact `devhaven` command you are about to run if the user needs transparency
- summarize state transitions in DevHaven terms, for example "closed the current workspace project" rather than "called a mutation"
- include the failing command and returned error code when something breaks

## Current Scope

This draft skill is intentionally optimized for Phase 1:

- status and capability discovery
- workspace lifecycle
- Project / Commit / Git tool window control

Do not assume `run`, `git`, `commit`, `diff`, `editor`, `notification`, or `update` namespaces exist unless `devhaven capabilities --json` says they do.
