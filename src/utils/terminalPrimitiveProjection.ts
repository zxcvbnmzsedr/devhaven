import type {
  TerminalPrimitiveAgentPid,
  TerminalPrimitiveProjection,
  TerminalPrimitiveStatus,
  TerminalPrimitiveTree,
} from "../models/terminalPrimitives";

function keepLatestByKey<T extends { key: string; updatedAt: number }>(
  values: T[] | null | undefined,
): Record<string, T> {
  return (values ?? []).reduce<Record<string, T>>((accumulator, value) => {
    const current = accumulator[value.key];
    if (!current || value.updatedAt >= current.updatedAt) {
      accumulator[value.key] = value;
    }
    return accumulator;
  }, {});
}

export function projectTerminalPrimitives(
  tree: TerminalPrimitiveTree,
): TerminalPrimitiveProjection {
  const statuses = keepLatestByKey<TerminalPrimitiveStatus>(tree?.statuses);
  const agentPids = keepLatestByKey<TerminalPrimitiveAgentPid>(tree?.agentPids);
  return {
    statusesByKey: statuses,
    agentPidsByKey: agentPids,
  };
}
