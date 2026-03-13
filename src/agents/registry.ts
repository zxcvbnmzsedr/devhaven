import type { PaneAgentProvider } from "../models/agent.ts";
import { claudeCodePaneAgentAdapter } from "./adapters/claudeCode.ts";
import { codexPaneAgentAdapter } from "./adapters/codex.ts";
import { iflowPaneAgentAdapter } from "./adapters/iflow.ts";
import type { PaneAgentAdapter } from "./adapters/types.ts";

const PANE_AGENT_ADAPTERS: Record<PaneAgentProvider, PaneAgentAdapter> = {
  codex: codexPaneAgentAdapter,
  "claude-code": claudeCodePaneAgentAdapter,
  iflow: iflowPaneAgentAdapter,
};

export function getPaneAgentAdapter(provider: PaneAgentProvider): PaneAgentAdapter {
  return PANE_AGENT_ADAPTERS[provider];
}

export function listPaneAgentAdapters(): PaneAgentAdapter[] {
  return Object.values(PANE_AGENT_ADAPTERS);
}
