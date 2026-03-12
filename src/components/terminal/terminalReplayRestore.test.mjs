import assert from "node:assert/strict";
import test from "node:test";

import { buildTerminalReplayRestorePlan } from "./terminalReplayRestore.ts";

test("buildTerminalReplayRestorePlan keeps replay history separate from live output", () => {
  const replayQuery = "\u001b[6n";
  const replayResponse = "\u001b[4;1R";
  const replayData = `prompt${replayQuery}`;
  const bufferedOutput = `${replayQuery}${replayResponse}tail`;

  const plan = buildTerminalReplayRestorePlan("", replayData, bufferedOutput);

  assert.equal(plan.historicalState, replayData);
  assert.equal(plan.liveState, `${replayResponse}tail`);
});

test("buildTerminalReplayRestorePlan drops live output already covered by replay history", () => {
  const replayData = "abcdef";
  const bufferedOutput = "cdef";

  const plan = buildTerminalReplayRestorePlan("", replayData, bufferedOutput);

  assert.equal(plan.historicalState, replayData);
  assert.equal(plan.liveState, "");
});

test("buildTerminalReplayRestorePlan preserves non-overlapping live output", () => {
  const baseState = "cached:";
  const replayData = "hello";
  const bufferedOutput = "world";

  const plan = buildTerminalReplayRestorePlan(baseState, replayData, bufferedOutput);

  assert.equal(plan.historicalState, "cached:hello");
  assert.equal(plan.liveState, "world");
});
