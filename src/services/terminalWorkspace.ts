import { invokeCommand } from "../platform/commandClient";
import { listenEvent } from "../platform/eventClient";
import type { TerminalWorkspace, TerminalWorkspaceSummary } from "../models/terminal";

export const TERMINAL_WORKSPACE_SYNC_EVENT = "terminal-workspace-sync";

export type TerminalWorkspaceSyncPayload = {
  projectPath: string;
  workspace?: TerminalWorkspace | null;
  sourceClientId?: string | null;
  deleted?: boolean;
  updatedAt: number;
};

export async function loadTerminalWorkspace(projectPath: string): Promise<TerminalWorkspace | null> {
  return invokeCommand<TerminalWorkspace | null>("load_terminal_workspace", { projectPath });
}

export async function saveTerminalWorkspace(
  projectPath: string,
  workspace: TerminalWorkspace,
  sourceClientId?: string,
): Promise<void> {
  await invokeCommand("save_terminal_workspace", { projectPath, workspace, sourceClientId });
}

export async function deleteTerminalWorkspace(projectPath: string, sourceClientId?: string): Promise<void> {
  await invokeCommand("delete_terminal_workspace", { projectPath, sourceClientId });
}

export async function listTerminalWorkspaceSummaries(): Promise<TerminalWorkspaceSummary[]> {
  return invokeCommand<TerminalWorkspaceSummary[]>("list_terminal_workspace_summaries");
}

export async function listenTerminalWorkspaceSync(
  handler: (event: { payload: TerminalWorkspaceSyncPayload }) => void,
) {
  return listenEvent<TerminalWorkspaceSyncPayload>(TERMINAL_WORKSPACE_SYNC_EVENT, handler);
}
