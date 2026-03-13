import assert from "node:assert/strict";
import test from "node:test";

import { resolveReplayModeOnUnmount } from "./terminalReplayModePolicy.ts";

test("resolveReplayModeOnUnmount keeps replay active on preserve unmount by default", () => {
  assert.equal(
    resolveReplayModeOnUnmount({
      preserveSessionOnUnmount: true,
    }),
    null,
  );
});

test("resolveReplayModeOnUnmount only parks replay when explicitly requested", () => {
  assert.equal(
    resolveReplayModeOnUnmount({
      preserveSessionOnUnmount: true,
      downgradeReplayOnPreserveUnmount: true,
    }),
    "parked",
  );

  assert.equal(
    resolveReplayModeOnUnmount({
      preserveSessionOnUnmount: false,
      downgradeReplayOnPreserveUnmount: true,
    }),
    null,
  );
});
