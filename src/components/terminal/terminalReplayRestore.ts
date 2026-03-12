const REPLAY_OVERLAP_SCAN_MAX_CHARS = 64 * 1024;

function resolveReplayAppendSuffix(existing: string, incoming: string): string {
  if (!existing || !incoming) {
    return incoming;
  }

  const maxOverlap = Math.min(REPLAY_OVERLAP_SCAN_MAX_CHARS, existing.length, incoming.length);
  for (let overlap = maxOverlap; overlap > 0; overlap -= 1) {
    if (existing.endsWith(incoming.slice(0, overlap))) {
      return incoming.slice(overlap);
    }
  }

  return incoming;
}

export function mergeReplayOutput(existing: string, incoming: string): string {
  return existing + resolveReplayAppendSuffix(existing, incoming);
}

export function buildTerminalReplayRestorePlan(
  baseState: string,
  replayData: string | null | undefined,
  bufferedOutput: string,
) {
  const historicalState = replayData ? mergeReplayOutput(baseState, replayData) : baseState;
  const liveState = resolveReplayAppendSuffix(historicalState, bufferedOutput);

  return {
    historicalState,
    liveState,
  };
}
