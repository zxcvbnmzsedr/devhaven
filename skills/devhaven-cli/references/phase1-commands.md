# Phase 1 Commands

Use this file only for the Phase 1 command surface. Do not assume later namespaces exist unless `devhaven capabilities --json` reports them.

## Discovery

### Check CLI availability

```bash
command -v devhaven
```

If this fails, stop and explain that the local DevHaven build does not ship the CLI yet.

### Check supported capabilities

```bash
devhaven capabilities --json
```

Expected use:

- discover supported namespaces and commands
- detect older builds that only expose `status`
- avoid guessing unimplemented commands

Fallback:

```bash
devhaven status --json
```

## State Queries

### Get app status

```bash
devhaven status --json
```

Use this to answer:

- is DevHaven running
- what workspace is active
- whether the CLI is connected to a live app instance

### List open workspaces

```bash
devhaven workspace list --json
```

Use this before retrying a failed `--current` mutation.

Useful fields to expect when implemented:

- `projectPath`
- `rootProjectPath`
- `kind`
- `isActive`
- `workspaceId`
- `workspaceName`

## Workspace Mutations

### Enter a workspace

```bash
devhaven workspace enter --path /abs/path --json
```

Use when the user wants to open or resume a project in DevHaven.

### Activate an already-open workspace

```bash
devhaven workspace activate --path /abs/path --json
```

Use when the target is already open and the user wants focus moved there without opening a new session.

### Exit the workspace view

```bash
devhaven workspace exit --json
```

Meaning:

- leave the workspace view
- keep the underlying session alive

### Close the current session

```bash
devhaven workspace close --current --scope session --json
```

Meaning:

- close only the current workspace session
- do not assume it closes the entire root project or workspace group

### Close the current project entry

```bash
devhaven workspace close --current --scope project --json
```

Meaning:

- close the current root project or workspace root when applicable
- use this for task-finished self-bootstrap flows

## Tool Windows

### Show a tool window

```bash
devhaven tool-window show --kind git --json
```

### Hide a tool window

```bash
devhaven tool-window hide --kind commit --json
```

### Toggle a tool window

```bash
devhaven tool-window toggle --kind project --json
```

Valid Phase 1 kinds:

- `project`
- `commit`
- `git`

## Recovery Patterns

### `--current` failed

1. Run `devhaven workspace list --json`
2. Identify the right target explicitly
3. Re-run with `--path` or a stable returned identifier

### command unsupported

1. Re-run `devhaven capabilities --json`
2. Confirm the namespace is absent
3. Tell the user this build does not implement that command yet

### app not running

1. Surface the error directly
2. Do not click the GUI
3. Only launch DevHaven if the user asked for it or the CLI contract explicitly supports it
