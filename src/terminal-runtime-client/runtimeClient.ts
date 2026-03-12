import { invokeCommand } from "../platform/commandClient";
import type {
  TerminalLayoutSnapshot,
  TerminalLayoutSnapshotSummary,
  TerminalWindowLayoutChangedPayload,
  TerminalWorkspaceRestoredPayload,
} from "../models/terminal";
import {
  listenTerminalWindowLayoutChanged,
  listenTerminalWorkspaceRestored,
} from "./subscriptions";

const LOAD_LAYOUT_SNAPSHOT_COMMAND = "load_terminal_layout_snapshot";
const SAVE_LAYOUT_SNAPSHOT_COMMAND = "save_terminal_layout_snapshot";
const DELETE_LAYOUT_SNAPSHOT_COMMAND = "delete_terminal_layout_snapshot";
const LIST_LAYOUT_SNAPSHOT_SUMMARIES_COMMAND = "list_terminal_layout_snapshot_summaries";

export async function loadTerminalLayoutSnapshot(projectPath: string): Promise<TerminalLayoutSnapshot | null> {
  return invokeCommand<TerminalLayoutSnapshot | null>(LOAD_LAYOUT_SNAPSHOT_COMMAND, { projectPath });
}

export async function saveTerminalLayoutSnapshot(
  projectPath: string,
  snapshot: TerminalLayoutSnapshot,
  sourceClientId?: string,
): Promise<void> {
  await invokeCommand<void>(SAVE_LAYOUT_SNAPSHOT_COMMAND, {
    projectPath,
    snapshot,
    sourceClientId,
  });
}

export async function deleteTerminalLayoutSnapshot(projectPath: string, sourceClientId?: string): Promise<void> {
  await invokeCommand<void>(DELETE_LAYOUT_SNAPSHOT_COMMAND, { projectPath, sourceClientId });
}

export async function listTerminalLayoutSnapshotSummaries(): Promise<TerminalLayoutSnapshotSummary[]> {
  return invokeCommand<TerminalLayoutSnapshotSummary[]>(LIST_LAYOUT_SNAPSHOT_SUMMARIES_COMMAND);
}

export async function listenTerminalLayoutSnapshotChanged(
  handler: (event: { payload: TerminalWindowLayoutChangedPayload }) => void,
) {
  return listenTerminalWindowLayoutChanged(handler);
}

export async function listenTerminalRuntimeWorkspaceRestored(
  handler: (event: { payload: TerminalWorkspaceRestoredPayload }) => void,
) {
  return listenTerminalWorkspaceRestored(handler);
}
