import { invokeCommand } from "../platform/commandClient";
import { listenEvent } from "../platform/eventClient";

import type {
  FinishQuickCommandRequest,
  ListQuickCommandsRequest,
  QuickCommandEvent,
  QuickCommandJob,
  QuickCommandSnapshot,
  StartQuickCommandRequest,
  StopQuickCommandRequest,
} from "../models/quickCommands";

export const QUICK_COMMAND_START_COMMAND = "quick_command_start";
export const QUICK_COMMAND_STOP_COMMAND = "quick_command_stop";
export const QUICK_COMMAND_FINISH_COMMAND = "quick_command_finish";
export const QUICK_COMMAND_LIST_COMMAND = "quick_command_list";
export const QUICK_COMMAND_SNAPSHOT_COMMAND = "quick_command_snapshot";
export const QUICK_COMMAND_EVENT = "quick-command-event";

export async function startQuickCommand(request: StartQuickCommandRequest): Promise<QuickCommandJob> {
  return invokeCommand<QuickCommandJob>(QUICK_COMMAND_START_COMMAND, {
    projectId: request.projectId,
    projectPath: request.projectPath,
    scriptId: request.scriptId,
    command: request.command,
    windowLabel: request.windowLabel,
  });
}

export async function stopQuickCommand(request: StopQuickCommandRequest): Promise<QuickCommandJob> {
  return invokeCommand<QuickCommandJob>(QUICK_COMMAND_STOP_COMMAND, {
    jobId: request.jobId,
    force: request.force,
  });
}

export async function finishQuickCommand(request: FinishQuickCommandRequest): Promise<QuickCommandJob> {
  return invokeCommand<QuickCommandJob>(QUICK_COMMAND_FINISH_COMMAND, {
    jobId: request.jobId,
    exitCode: request.exitCode,
    error: request.error,
  });
}

export async function listQuickCommands(request?: ListQuickCommandsRequest): Promise<QuickCommandJob[]> {
  return invokeCommand<QuickCommandJob[]>(QUICK_COMMAND_LIST_COMMAND, {
    projectPath: request?.projectPath,
  });
}

export async function getQuickCommandSnapshot(): Promise<QuickCommandSnapshot> {
  return invokeCommand<QuickCommandSnapshot>(QUICK_COMMAND_SNAPSHOT_COMMAND);
}

export async function listenQuickCommandEvent(handler: (event: { payload: QuickCommandEvent }) => void) {
  return listenEvent<QuickCommandEvent>(QUICK_COMMAND_EVENT, handler);
}
