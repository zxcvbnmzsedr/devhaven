import type { AgentShellFamily, PaneAgentProvider } from "../../models/agent.ts";

export type PaneAgentAdapter = {
  id: PaneAgentProvider;
  label: string;
  supportsModelSelection: boolean;
  buildBaseCommand: (input?: {
    model?: string | null;
    prompt?: string | null;
    fullAccess?: boolean;
  }) => string;
  buildLaunchCommand: (input?: {
    model?: string | null;
    prompt?: string | null;
    fullAccess?: boolean;
    shellFamily?: AgentShellFamily;
  }) => string;
};
