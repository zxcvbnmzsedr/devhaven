import type { AgentShellFamily } from "../models/agent";

export const DEVHAVEN_AGENT_STARTED_MARKER = "[DevHaven Agent Started]";
export const DEVHAVEN_AGENT_EXIT_MARKER_PREFIX = "[DevHaven Agent Exit:";

export function quoteShellArg(value: string): string {
  return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

export function wrapAgentBaseCommand(
  baseCommand: string,
  shellFamily: AgentShellFamily,
): string {
  if (shellFamily === "powershell") {
    return [
      `Write-Host '${DEVHAVEN_AGENT_STARTED_MARKER}'`,
      `& { ${baseCommand} }`,
      `Write-Host ('${DEVHAVEN_AGENT_EXIT_MARKER_PREFIX}' + $LASTEXITCODE + ']')`,
    ].join("; ");
  }

  return [
    `printf '%s\\n' '${DEVHAVEN_AGENT_STARTED_MARKER}'`,
    `( ${baseCommand} )`,
    `printf '%s%s%s\\n' '${DEVHAVEN_AGENT_EXIT_MARKER_PREFIX}' "$?" ']'`,
  ].join("; ");
}
