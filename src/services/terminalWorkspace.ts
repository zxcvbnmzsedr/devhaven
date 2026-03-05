import { invokeCommand } from "../platform/commandClient";
import type { TerminalWorkspace, TerminalWorkspaceSummary } from "../models/terminal";

export async function loadTerminalWorkspace(projectPath: string): Promise<TerminalWorkspace | null> {
  return invokeCommand<TerminalWorkspace | null>("load_terminal_workspace", { projectPath });
}

export async function saveTerminalWorkspace(projectPath: string, workspace: TerminalWorkspace): Promise<void> {
  await invokeCommand("save_terminal_workspace", { projectPath, workspace });
}

export async function deleteTerminalWorkspace(projectPath: string): Promise<void> {
  await invokeCommand("delete_terminal_workspace", { projectPath });
}

export async function listTerminalWorkspaceSummaries(): Promise<TerminalWorkspaceSummary[]> {
  return invokeCommand<TerminalWorkspaceSummary[]>("list_terminal_workspace_summaries");
}
