import { invokeCommand } from "../platform/commandClient";
import { listenEvent } from "../platform/eventClient";

import type {
  FinishQuickCommandRequest,
  ListQuickCommandsRequest,
  QuickCommandJob,
  QuickCommandRuntimeProjection,
  QuickCommandStateChangedPayload,
  StartQuickCommandRequest,
  StopQuickCommandRequest,
} from "../models/quickCommands";
import { QUICK_COMMAND_STATE_CHANGED_EVENT } from "../terminal-runtime-client/subscriptions";

export const QUICK_COMMAND_START_COMMAND = "quick_command_start";
export const QUICK_COMMAND_STOP_COMMAND = "quick_command_stop";
export const QUICK_COMMAND_FINISH_COMMAND = "quick_command_finish";
export const QUICK_COMMAND_LIST_COMMAND = "quick_command_list";
export const QUICK_COMMAND_RUNTIME_SNAPSHOT_COMMAND = "quick_command_runtime_snapshot";

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

export async function getQuickCommandRuntimeProjection(projectPath?: string): Promise<QuickCommandRuntimeProjection> {
  return invokeCommand<QuickCommandRuntimeProjection>(QUICK_COMMAND_RUNTIME_SNAPSHOT_COMMAND, { projectPath });
}

export async function listenQuickCommandStateChanged(
  handler: (event: { payload: QuickCommandStateChangedPayload }) => void,
) {
  return listenEvent<QuickCommandStateChangedPayload>(QUICK_COMMAND_STATE_CHANGED_EVENT, handler);
}
