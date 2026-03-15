import type {
  ControlPlaneAgentPidPrimitive,
  ControlPlaneStatusPrimitive,
  ControlPlaneTree,
  ControlPlaneWorkspaceTree,
} from "./controlPlane";

export type TerminalPrimitiveStatus = ControlPlaneStatusPrimitive;
export type TerminalPrimitiveAgentPid = ControlPlaneAgentPidPrimitive;

export type TerminalPrimitiveProjection = {
  statusesByKey: Record<string, TerminalPrimitiveStatus>;
  agentPidsByKey: Record<string, TerminalPrimitiveAgentPid>;
};

export type TerminalPrimitiveTree =
  | Pick<ControlPlaneTree, "statuses" | "agentPids">
  | Pick<ControlPlaneWorkspaceTree, "statuses" | "agentPids">
  | null
  | undefined;
