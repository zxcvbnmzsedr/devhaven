import type {
  TerminalLayoutSnapshot,
  TerminalLayoutSnapshotSummary,
  TerminalWindowLayoutChangedPayload,
  TerminalWorkspaceRestoredPayload,
} from "../models/terminal";
import {
  listenTerminalWindowLayoutChanged,
  listenTerminalWorkspaceRestored as listenTerminalWorkspaceRestoredEvent,
  TERMINAL_WINDOW_LAYOUT_CHANGED_EVENT,
} from "../terminal-runtime-client/subscriptions";
import {
  deleteTerminalLayoutSnapshot,
  listTerminalLayoutSnapshotSummaries,
  loadTerminalLayoutSnapshot,
  saveTerminalLayoutSnapshot,
} from "../terminal-runtime-client/runtimeClient";

export const TERMINAL_LAYOUT_CHANGED_EVENT = TERMINAL_WINDOW_LAYOUT_CHANGED_EVENT;

// ==================== 新版布局快照服务 ====================

export async function loadTerminalLayout(
  projectPath: string,
): Promise<TerminalLayoutSnapshot | null> {
  return loadTerminalLayoutSnapshot(projectPath);
}

export async function saveTerminalLayout(
  projectPath: string,
  snapshot: TerminalLayoutSnapshot,
  sourceClientId?: string,
): Promise<void> {
  await saveTerminalLayoutSnapshot(projectPath, snapshot, sourceClientId);
}

export async function deleteTerminalLayout(projectPath: string, sourceClientId?: string): Promise<void> {
  await deleteTerminalLayoutSnapshot(projectPath, sourceClientId);
}

export async function listTerminalLayoutSummaries(): Promise<TerminalLayoutSnapshotSummary[]> {
  return listTerminalLayoutSnapshotSummaries();
}

export async function listenTerminalLayoutChanged(
  handler: (event: { payload: TerminalWindowLayoutChangedPayload }) => void,
) {
  return listenTerminalWindowLayoutChanged(handler);
}

export async function listenTerminalWorkspaceRestored(
  handler: (event: { payload: TerminalWorkspaceRestoredPayload }) => void,
) {
  return listenTerminalWorkspaceRestoredEvent(handler);
}
