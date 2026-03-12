# Terminal Workspace Once-Cutover Plan

Goal: replace the existing terminal workspace runtime with a Rust-owned mux-lite runtime, structured layout snapshots, projection-based frontend shell, and scoped terminal/runtime events.

Phases:
1. Runtime truth source
2. Typed/scoped event routing
3. Layout snapshot + persistence cutover
4. Frontend runtime client + shell/projections
5. Unified pane system
6. Import old workspaces + delete legacy paths
