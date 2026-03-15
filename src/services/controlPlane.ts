import { listenEvent } from "../platform/eventClient";
import { invokeCommand } from "../platform/commandClient";
import type {
  ControlPlaneChangedPayload,
  ControlPlaneTree,
  ControlPlaneWorkspaceTree,
} from "../models/controlPlane";

const DEVHAVEN_TREE_COMMAND = "devhaven_tree";
const DEVHAVEN_IDENTIFY_COMMAND = "devhaven_identify";
const DEVHAVEN_NOTIFY_COMMAND = "devhaven_notify";
const DEVHAVEN_NOTIFY_TARGET_COMMAND = "devhaven_notify_target";
const DEVHAVEN_AGENT_SESSION_EVENT_COMMAND = "devhaven_agent_session_event";
const DEVHAVEN_SET_STATUS_COMMAND = "devhaven_set_status";
const DEVHAVEN_CLEAR_STATUS_COMMAND = "devhaven_clear_status";
const DEVHAVEN_SET_AGENT_PID_COMMAND = "devhaven_set_agent_pid";
const DEVHAVEN_CLEAR_AGENT_PID_COMMAND = "devhaven_clear_agent_pid";
const DEVHAVEN_MARK_NOTIFICATION_READ_COMMAND = "devhaven_mark_notification_read";
const DEVHAVEN_MARK_NOTIFICATION_UNREAD_COMMAND = "devhaven_mark_notification_unread";

export const DEVHAVEN_CONTROL_PLANE_CHANGED_EVENT = "devhaven-control-plane-changed";

export async function getControlPlaneTree(params: {
  projectPath: string;
  workspaceId?: string | null;
}): Promise<ControlPlaneTree | null> {
  return invokeCommand<ControlPlaneTree | null>(DEVHAVEN_TREE_COMMAND, params);
}

export async function loadControlPlaneTree(params: {
  projectPath: string;
  workspaceId?: string | null;
}): Promise<ControlPlaneWorkspaceTree | null> {
  const tree = await getControlPlaneTree(params);
  if (!tree) {
    return null;
  }
  return {
    workspaceId: tree.workspaceId,
    projectPath: tree.projectPath,
    surfaces: tree.panes,
    notifications: tree.notifications,
    statuses: tree.statuses ?? [],
    agentPids: tree.agentPids ?? [],
  };
}

export async function identifyControlPlane(params: {
  terminalSessionId?: string | null;
  workspaceId?: string | null;
  paneId?: string | null;
  surfaceId?: string | null;
}) {
  return invokeCommand(DEVHAVEN_IDENTIFY_COMMAND, params);
}

export async function notifyControlPlane(params: Record<string, unknown>) {
  return invokeCommand(DEVHAVEN_NOTIFY_COMMAND, params);
}

export async function notifyTargetControlPlane(params: Record<string, unknown>) {
  return invokeCommand(DEVHAVEN_NOTIFY_TARGET_COMMAND, params);
}

export async function emitAgentSessionEvent(params: Record<string, unknown>) {
  return invokeCommand(DEVHAVEN_AGENT_SESSION_EVENT_COMMAND, params);
}

export async function setControlPlaneStatus(params: Record<string, unknown>) {
  return invokeCommand(DEVHAVEN_SET_STATUS_COMMAND, params);
}

export async function clearControlPlaneStatus(params: Record<string, unknown>) {
  return invokeCommand(DEVHAVEN_CLEAR_STATUS_COMMAND, params);
}

export async function setControlPlaneAgentPid(params: Record<string, unknown>) {
  return invokeCommand(DEVHAVEN_SET_AGENT_PID_COMMAND, params);
}

export async function clearControlPlaneAgentPid(params: Record<string, unknown>) {
  return invokeCommand(DEVHAVEN_CLEAR_AGENT_PID_COMMAND, params);
}

export async function markControlPlaneNotificationRead(notificationId: string) {
  return invokeCommand(DEVHAVEN_MARK_NOTIFICATION_READ_COMMAND, { notificationId });
}

export async function markControlPlaneNotificationUnread(notificationId: string) {
  return invokeCommand(DEVHAVEN_MARK_NOTIFICATION_UNREAD_COMMAND, { notificationId });
}

export async function listenControlPlaneChanged(
  handler: (event: { payload: ControlPlaneChangedPayload }) => void,
) {
  return listenEvent<ControlPlaneChangedPayload>(DEVHAVEN_CONTROL_PLANE_CHANGED_EVENT, handler);
}
